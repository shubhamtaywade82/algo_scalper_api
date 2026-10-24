# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::OptionChains' do
  describe 'GET /api/option_chain/:index_key' do
    let(:analyzer_double) { instance_double(Options::DerivativeChainAnalyzer) }

    before do
      allow(Options::DerivativeChainAnalyzer).to receive(:new).with(index_key: 'NIFTY').and_return(analyzer_double)
      allow(Options::DerivativeChainAnalyzer).to receive(:new).with(index_key: 'NIFTY', config: { strike_window_steps: 5 }).and_return(analyzer_double)

      allow(analyzer_double).to receive_messages(spot_ltp: 24_398.70, find_nearest_expiry: '2026-07-09')
      allow(analyzer_double).to receive(:load_chain_for_expiry).with('2026-07-09', 24_398.70).and_return([
                                                                                                           {
                                                                                                             strike: 24_400.0,
                                                                                                             type: 'CE',
                                                                                                             security_id: '12345',
                                                                                                             segment: 'NSE_FNO',
                                                                                                             lot_size: 75,
                                                                                                             ltp: 120.50,
                                                                                                             oi: 15_000,
                                                                                                             oi_change: 2500,
                                                                                                             bid: 120.10,
                                                                                                             ask: 120.90,
                                                                                                             iv: 12.5,
                                                                                                             volume: 50_000,
                                                                                                             prev_close: 110.0,
                                                                                                             delta: 0.50,
                                                                                                             gamma: 0.001,
                                                                                                             theta: -12.5,
                                                                                                             vega: 15.2
                                                                                                           },
                                                                                                           {
                                                                                                             strike: 24_400.0,
                                                                                                             type: 'PE',
                                                                                                             security_id: '12346',
                                                                                                             segment: 'NSE_FNO',
                                                                                                             lot_size: 75,
                                                                                                             ltp: 95.20,
                                                                                                             oi: 12_000,
                                                                                                             oi_change: 1800,
                                                                                                             bid: 95.00,
                                                                                                             ask: 95.40,
                                                                                                             iv: 13.2,
                                                                                                             volume: 45_000,
                                                                                                             prev_close: 105.0,
                                                                                                             delta: -0.49,
                                                                                                             gamma: 0.001,
                                                                                                             theta: -11.8,
                                                                                                             vega: 14.8
                                                                                                           }
                                                                                                         ])
    end

    it 'returns option chain snapshot for valid index' do
      get '/api/option_chain/NIFTY'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['index_key']).to eq('NIFTY')
      expect(body['spot']).to eq(24_398.70)
      expect(body['atm_strike']).to eq(24_400.0)
      expect(body['expiry']).to eq('2026-07-09')
      expect(body['legs'].size).to eq(2)

      ce = body['legs'].find { |l| l['type'] == 'CE' }
      expect(ce['strike']).to eq(24_400.0)
      expect(ce['ltp']).to eq(120.50)
      expect(ce['delta']).to eq(0.50)
    end

    it 'returns bad request for unknown index' do
      get '/api/option_chain/INVALID'

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to match(/unknown index key/i)
    end

    context 'when spot price cannot be resolved' do
      before do
        allow(analyzer_double).to receive(:spot_ltp).and_return(nil)
        allow(Live::TickCache).to receive(:fetch).and_return(nil)
      end

      it 'returns unprocessable entity' do
        get '/api/option_chain/NIFTY'

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to match(/could not resolve spot price/i)
      end
    end
  end
end
