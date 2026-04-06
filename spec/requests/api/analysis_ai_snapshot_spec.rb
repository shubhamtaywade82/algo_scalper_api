# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/analysis/:index_key/ai_snapshot' do # rubocop:disable RSpec/DescribeClass
  let(:instrument) { create(:instrument, :nifty_future) }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([
                                                                    { key: 'NIFTY', segment: instrument.exchange_segment, sid: instrument.security_id.to_s }
                                                                  ])
    allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
    allow(Live::TickCache).to receive(:ltp).and_return(22_450.0)
    allow(AnalysisStore).to receive(:read_all).and_return({
      smc: { data: { 'trend' => 'bullish' } },
      regime: { data: { 'label' => 'trending' } }
    })
    allow(CalibrationRun).to receive(:where).and_return(CalibrationRun.none)
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).and_return(false)
  end

  context 'when OllamaClient returns a response' do
    before do
      client = instance_double(Services::Ai::OllamaClient, enabled?: true,
                                                           chat: 'Bullish outlook. Key level 22000.')
      allow(Services::Ai::OllamaClient).to receive(:instance).and_return(client)
    end

    it 'returns 200 with snapshot and generated_at' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to have_key('snapshot')
      expect(json).to have_key('generated_at')
    end

    it 'returns the AI response as snapshot' do
      post '/api/analysis/NIFTY/ai_snapshot'
      json = response.parsed_body
      expect(json['snapshot']).to include('Bullish outlook')
    end
  end

  # OllamaClient#chat rescues all StandardError internally and returns nil on failure
  # (timeouts, connection errors, etc.). This is the actual production failure path.
  context 'when OllamaClient returns nil (service failure / timeout)' do
    before do
      client = instance_double(Services::Ai::OllamaClient, enabled?: true, chat: nil)
      allow(Services::Ai::OllamaClient).to receive(:instance).and_return(client)
    end

    it 'returns 503' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:service_unavailable)
    end

    it 'returns a human-readable error' do
      post '/api/analysis/NIFTY/ai_snapshot'
      json = response.parsed_body
      expect(json['error']).to include('unavailable')
    end
  end

  context 'when AI client is not enabled' do
    before do
      client = instance_double(Services::Ai::OllamaClient, enabled?: false)
      allow(Services::Ai::OllamaClient).to receive(:instance).and_return(client)
    end

    it 'returns 503 without calling chat' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:service_unavailable)
      json = response.parsed_body
      expect(json['error']).to include('not configured')
    end
  end

  context 'when generative AI is market-gated' do
    let(:client) do
      instance_double(Services::Ai::OllamaClient, enabled?: true,
                                                  chat: 'Should not run')
    end

    before do
      allow(Services::Ai::OllamaClient).to receive(:instance).and_return(client)
      allow(Ai::GenerativeAiMarketGate).to receive(:skip?) do |force: false|
        force ? false : true
      end
    end

    it 'returns 422 and does not call chat' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:unprocessable_content)
      expect(client).not_to have_received(:chat)
    end

    it 'allows force=true to run chat' do
      post '/api/analysis/NIFTY/ai_snapshot', params: { force: 'true' }
      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:chat)
    end
  end

  context 'with an unknown index_key' do
    before do
      allow(IndexConfigLoader).to receive(:load_indices).and_return([])
      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nil)
    end

    it 'returns 404' do
      post '/api/analysis/UNKNOWN/ai_snapshot'
      expect(response).to have_http_status(:not_found)
    end
  end
end
