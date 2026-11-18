# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/analysis/:index_key' do # rubocop:disable RSpec/DescribeClass
  let(:instrument) { create(:instrument, :nifty_future, symbol_name: 'NIFTY') }
  let(:stored) do
    {
      smc: { data: { 'trend' => 'bullish' }, validity: 'fresh' },
      ai: { data: { 'text' => 'ok' }, validity: 'stale' },
      regime: { data: { 'label' => 'trending' }, validity: 'fresh' }
    }
  end
  let(:stale) { [] }
  let(:calls) { [] }

  before do
    allow(IndexConfigLoader).to receive(:index_instrument).with('NIFTY').and_return(instrument)
    allow(AnalysisStore).to receive(:read_all).with('NIFTY') do
      calls << :read_all
      stored
    end
    allow(AnalysisStore).to receive(:stale_components).with('NIFTY').and_return(stale)
    allow(AnalysisJob).to receive(:perform_now) { calls << :refresh }
    allow(Thread).to receive(:new).and_yield # run the background refresh inline
    allow(Live::TickCache).to receive(:ltp).and_return(24_500.5)
    allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return('opening_drive')
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).with(force: false).and_return(true)
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: { institutional_trailing: { nifty: { step: 2 } }, time_stop: 20, profit_floor: 0.1 },
      indices: [{ key: 'NIFTY', risk_model: 'tight', direction: 'both' }]
    )
  end

  it 'returns 404 for an unknown index' do
    allow(IndexConfigLoader).to receive(:index_instrument).with('NOPE').and_return(nil)

    get '/api/analysis/nope'

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'Index not found')
  end

  it 'assembles the stored analysis, live price, session flags and config summary' do
    get '/api/analysis/nifty'

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'index_key' => 'NIFTY', 'symbol' => 'NIFTY', 'ltp' => 24_500.5,
      'session' => { 'market_closed' => false, 'generative_ai_gated' => true },
      'smc' => { 'trend' => 'bullish' }, 'smc_validity' => 'fresh',
      'ai_analysis' => { 'text' => 'ok' }, 'ai_validity' => 'stale',
      'market_regime' => { 'label' => 'trending' }, 'regime_validity' => 'fresh',
      'time_regime' => 'opening_drive', 'active_positions' => 0, 'background_refresh' => nil,
      'config' => { 'trailing' => { 'step' => 2 }, 'time_stop' => 20, 'profit_floor' => 0.1,
                    'risk_model' => 'tight', 'direction' => 'both' }
    )
  end

  context 'when components are stale' do
    let(:stale) { %i[smc ai] }

    it 'reads the stored analysis before starting the refresh, and says what is refreshing' do
      get '/api/analysis/nifty'

      expect(calls).to eq(%i[read_all refresh])
      expect(response.parsed_body['background_refresh']).to eq('refreshing' => %w[smc ai], 'message' => 'Background refresh triggered')
    end

    it 'passes force through to the refresh job' do
      get '/api/analysis/nifty', params: { force: 'true' }

      expect(AnalysisJob).to have_received(:perform_now).with('NIFTY', force: true)
    end
  end

  it 'does not start a refresh when nothing is stale' do
    get '/api/analysis/nifty'

    expect(AnalysisJob).not_to have_received(:perform_now)
  end

  it 'degrades the time regime to null when its lookup fails' do
    allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_raise(StandardError, 'boom')

    get '/api/analysis/nifty'

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['time_regime']).to be_nil
  end

  it 'answers 500 with the error message on an unexpected failure' do
    allow(Live::TickCache).to receive(:ltp).and_raise(StandardError, 'cache down')

    get '/api/analysis/nifty'

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body).to eq('error' => 'internal_error', 'message' => 'cache down')
  end
end
