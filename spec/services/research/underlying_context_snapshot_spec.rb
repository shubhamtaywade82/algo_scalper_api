# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::UnderlyingContextSnapshot do
  describe '.at' do
    it 'returns {} when there is not enough candle history' do
      expect(described_class.at(symbol: 'NIFTY', timestamp: Time.zone.parse('2026-07-10 10:00:00'))).to eq({})
    end

    it 'computes ATR/ADX/RSI/MACD/VWAP once enough 1m candles are persisted' do
      base = Time.zone.parse('2026-07-10 09:15:00')
      price = 24_900.0
      40.times do |i|
        price += (i.even? ? 2 : -1)
        Candles::Record.create!(
          instrument_key: 'NIFTY', exchange_segment: 'NSE_IDX', security_id: '13', timeframe: '1m',
          ts: base + i.minutes, open: price, high: price + 3, low: price - 3, close: price + 1,
          volume: 1000, source: 'live'
        )
      end

      context = described_class.at(symbol: 'NIFTY', timestamp: base + 39.minutes)

      expect(context['close']).to be_a(Numeric)
      expect(context).to have_key('atr')
      expect(context).to have_key('adx')
      expect(context).to have_key('rsi')
      expect(context).to have_key('macd')
      expect(context['vwap']).to be_a(Numeric)
    end
  end
end
