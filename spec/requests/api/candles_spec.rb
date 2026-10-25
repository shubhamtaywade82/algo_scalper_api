# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API candles' do
  let(:nifty_instrument) do
    instance_double(Instrument,
                    security_id: '99920',
                    exchange_segment: 'NSE_I')
  end

  before do
    Rails.cache.clear
    allow(IndexConfigLoader).to receive(:load_indices).and_return(
      [{ key: 'NIFTY', sid: '99920', segment: 'NSE_I' }]
    )
    allow(Market::Calendar).to receive_messages(today_or_last_trading_day: Date.new(2026, 10, 23), trading_days_ago: Date.new(2026, 10, 20))
  end

  describe 'GET /api/candles/:index_key' do
    it 'returns 404 for an unknown index key' do
      get '/api/candles/BOGUS'
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('Index not found')
    end

    it 'returns 404 when the index config exists but the instrument row is missing' do
      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nil)

      get '/api/candles/NIFTY'
      expect(response).to have_http_status(:not_found)
    end

    context 'with a resolvable instrument' do
      before do
        allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nifty_instrument)
      end

      it 'returns serialized candles with defaults (interval 5, requested days)' do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(
          [
            { 'timestamp' => '2026-10-23T09:15:00+05:30', 'open' => '24100.5', 'high' => '24120.25',
              'low' => '24095.0', 'close' => '24115.75', 'volume' => '1234567' }
          ]
        )

        get '/api/candles/NIFTY', params: { days: 3 }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['index_key']).to eq('NIFTY')
        expect(body['interval']).to eq('5')
        candle = body['candles'].first
        expect(candle['open']).to eq(24_100.5)
        expect(candle['high']).to eq(24_120.25)
        expect(candle['low']).to eq(24_095.0)
        expect(candle['close']).to eq(24_115.75)
        expect(candle['volume']).to eq(1_234_567)
      end

      it 'accepts a valid interval and passes it through to the fetcher' do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return([])

        get '/api/candles/NIFTY', params: { interval: '15' }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['interval']).to eq('15')
        expect(DhanHQ::Models::HistoricalData).to have_received(:intraday)
          .with(hash_including(interval: '15', security_id: '99920', exchange_segment: 'NSE_I'))
      end

      it 'falls back to interval 5 for a disallowed interval' do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return([])

        get '/api/candles/NIFTY', params: { interval: '7' }

        expect(response.parsed_body['interval']).to eq('5')
      end

      it 'clamps days to the 1..30 window' do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return([])

        get '/api/candles/NIFTY', params: { days: 500 }

        expect(DhanHQ::Models::HistoricalData).to have_received(:intraday)
          .with(hash_including(from_date: '2026-10-20', to_date: '2026-10-23'))
      end

      it 'returns an empty candle list when the upstream fetch fails' do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, 'gateway down')

        get '/api/candles/NIFTY'

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['candles']).to eq([])
      end

      it 'renders internal_error when serialization itself explodes' do
        bad_bar = double('bad bar')
        allow(bad_bar).to receive(:[]).and_raise(StandardError, 'kaboom')
        # Bypass the cache layer: pass the poisoned bar straight through so the
        # raise happens in serialize_bar (inside index's rescue), not inside
        # fetch_bars (whose own rescue would swallow it into an empty list).
        allow(Rails.cache).to receive(:fetch).and_return([bad_bar])

        get '/api/candles/NIFTY'

        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body['error']).to eq('internal_error')
      end
    end
  end
end
