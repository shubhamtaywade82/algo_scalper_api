# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candle do
  describe 'type coercion' do
    it 'coerces OHLC values to float and volume to integer' do
      candle = described_class.new(
        timestamp: Time.zone.parse('2026-10-23 09:15:00'),
        open: '24100.5', high: '24120', low: '24095', close: '24115.75', volume: '1234567'
      )

      expect(candle.open).to eq(24_100.5)
      expect(candle.high).to eq(24_120.0)
      expect(candle.low).to eq(24_095.0)
      expect(candle.close).to eq(24_115.75)
      expect(candle.volume).to eq(1_234_567)
    end

    it 'keeps the raw timestamp' do
      ts = Time.zone.parse('2026-10-23 09:15:00')
      expect(described_class.new(timestamp: ts, open: 1, high: 2, low: 0.5, close: 1.5, volume: 10).timestamp).to eq(ts)
    end
  end

  describe '#bullish? / #bearish?' do
    it 'is bullish when close >= open' do
      candle = described_class.new(timestamp: Time.current, open: 100.0, high: 110.0, low: 99.0, close: 105.0, volume: 1)
      expect(candle).to be_bullish
      expect(candle).not_to be_bearish
    end

    it 'treats a doji (close == open) as bullish' do
      candle = described_class.new(timestamp: Time.current, open: 100.0, high: 101.0, low: 99.0, close: 100.0, volume: 1)
      expect(candle).to be_bullish
    end

    it 'is bearish when close < open' do
      candle = described_class.new(timestamp: Time.current, open: 100.0, high: 101.0, low: 98.0, close: 99.0, volume: 1)
      expect(candle).to be_bearish
      expect(candle).not_to be_bullish
    end
  end
end
