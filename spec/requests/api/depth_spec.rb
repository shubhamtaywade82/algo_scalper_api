# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API market depth' do
  describe 'GET /api/depth' do
    context 'with an index symbol resolvable to an ATM CE contract' do
      let(:analyzer) do
        instance_double(Options::DerivativeChainAnalyzer,
                        spot_ltp: 24_800.0,
                        find_nearest_expiry: Date.new(2026, 10, 29))
      end
      let(:options_scope) { double('Instrument options scope') }
      let(:contract) do
        instance_double(Instrument,
                        symbol_name: 'NIFTY 24800 CE',
                        security_id: '55501',
                        exchange_segment: 'NSE_FNO')
      end

      before do
        allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(analyzer)
        allow(Instrument).to receive(:options).and_return(options_scope)
        allow(options_scope).to receive(:find_by).and_return(contract)
      end

      it 'quotes the ATM CE contract and maps DhanHQ depth levels' do
        allow(DhanHQ::Models::MarketFeed).to receive(:quote).and_return(
          {
            'status' => 'success',
            'data' => {
              'NSE_FNO' => {
                '55501' => {
                  'depth' => {
                    'buy' => [
                      { 'price' => '120.50', 'quantity' => '150', 'orders' => 3 },
                      { 'price' => '120.45', 'quantity' => '75', 'orders' => 1 }
                    ],
                    'sell' => [
                      { 'price' => '120.60', 'quantity' => '225', 'orders' => 4 }
                    ]
                  }
                }
              }
            }
          }
        )

        get '/api/depth', params: { symbol: 'NIFTY' }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['symbol']).to eq('NIFTY 24800 CE')
        expect(body['bid']).to contain_exactly(
          { 'price' => 120.5, 'qty' => 150, 'orders' => 3 },
          { 'price' => 120.45, 'qty' => 75, 'orders' => 1 }
        )
        expect(body['ask']).to contain_exactly({ 'price' => 120.6, 'qty' => 225, 'orders' => 4 })
        expect(body['totalBidQty']).to eq(225)
        expect(body['totalAskQty']).to eq(225)
      end

      it 'falls back to the redis depth snapshot when the DhanHQ quote fails' do
        allow(DhanHQ::Models::MarketFeed).to receive(:quote).and_return({ 'status' => 'failure' })
        allow(Validators::MarketDataCache).to receive(:depth_snapshot).and_return(
          { best_bid: 120.5, best_bid_qty: 40, best_ask: 120.6, best_ask_qty: 60 }
        )

        get '/api/depth', params: { symbol: 'NIFTY' }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['symbol']).to eq('NIFTY 24800 CE')
        expect(body['bid']).to contain_exactly({ 'price' => 120.5, 'qty' => 40, 'orders' => 0 })
        expect(body['ask']).to contain_exactly({ 'price' => 120.6, 'qty' => 60, 'orders' => 0 })
        expect(body['totalBidQty']).to eq(40)
        expect(body['totalAskQty']).to eq(60)
      end

      it 'returns an empty depth when both DhanHQ and redis have nothing' do
        allow(DhanHQ::Models::MarketFeed).to receive(:quote).and_return({ 'status' => 'failure' })
        allow(Validators::MarketDataCache).to receive(:depth_snapshot).and_return(nil)

        get '/api/depth', params: { symbol: 'NIFTY' }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['symbol']).to eq('NIFTY ATM CE')
        expect(body['bid']).to eq([])
        expect(body['ask']).to eq([])
      end

      it 'returns an empty depth when the chain analyzer raises' do
        allow(Options::DerivativeChainAnalyzer).to receive(:new).and_raise(StandardError, 'chain down')

        get '/api/depth', params: { symbol: 'NIFTY' }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['bid']).to eq([])
      end
    end

    context 'with a non-index symbol' do
      it 'returns an empty depth when the instrument is unknown' do
        allow(Instrument).to receive(:find_by).and_return(nil)

        get '/api/depth', params: { symbol: 'TATASTEEL' }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['symbol']).to eq('TATASTEEL')
        expect(body['totalBidQty']).to eq(0)
        expect(body['totalAskQty']).to eq(0)
      end
    end
  end
end
