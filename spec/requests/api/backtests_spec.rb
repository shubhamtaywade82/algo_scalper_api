# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Backtests' do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  describe 'POST /api/backtests' do
    it 'enqueues EquityBacktestJob and returns a queued run id immediately' do
      allow(EquityBacktestJob).to receive(:perform_later)

      post '/api/backtests', params: { symbol: 'niftY', interval: '5', days_back: 45 }

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body['status']).to eq('queued')
      expect(EquityBacktestJob).to have_received(:perform_later)
        .with(body['backtest_run_id'], symbol: 'NIFTY', interval: '5', days_back: 45)
      expect(Rails.cache.read(EquityBacktestJob.cache_key(body['backtest_run_id']))).to eq(status: 'queued')
    end
  end

  describe 'GET /api/backtests/:id' do
    it 'returns not_found for an unknown or expired run' do
      get '/api/backtests/does-not-exist'

      expect(response).to have_http_status(:not_found)
    end

    it 'returns the cached state for a completed run' do
      Rails.cache.write(EquityBacktestJob.cache_key('run-1'), { status: 'completed', metrics: { totalTrades: 3 } })

      get '/api/backtests/run-1'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'completed', 'metrics' => { 'totalTrades' => 3 })
    end
  end
end
