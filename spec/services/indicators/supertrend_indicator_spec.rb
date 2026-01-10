# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::SupertrendIndicator do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:config) { { period: 7, multiplier: 3.0 } }
  let(:indicator) { described_class.new(series: series, config: config) }

  before do
    # Create enough candles for Supertrend calculation
    50.times do |i|
      price = 22_000.0 + (i * 10)
      candle = Candle.new(
        ts: Time.zone.parse('2024-01-01 10:00:00 IST') + i.minutes,
        open: price,
        high: price + 5,
        low: price - 5,
        close: price + 2,
        volume: 1000
      )
      series.add_candle(candle)
    end
  end

  describe '#initialize' do
    it 'initializes with series and config' do
      expect(indicator.series).to eq(series)
      expect(indicator.config).to eq(config)
    end

    it 'uses default config when not provided' do
      indicator_default = described_class.new(series: series)
      expect(indicator_default.config).to eq({})
    end
  end

  describe '#min_required_candles' do
    it 'returns minimum candles required' do
      min_candles = indicator.min_required_candles
      expect(min_candles).to be > 0
      expect(min_candles).to be_a(Integer)
    end
  end

  describe '#ready?' do
    it 'returns false when not enough candles' do
      expect(indicator.ready?(5)).to be false
    end

    it 'returns true when enough candles' do
      min_candles = indicator.min_required_candles
      expect(indicator.ready?(min_candles)).to be true
    end
  end

  describe '#calculate_at' do
    let(:index) { series.candles.size - 1 }

    it 'returns hash with required keys' do
      result = indicator.calculate_at(index)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:value)
      expect(result).to have_key(:direction)
      expect(result).to have_key(:confidence)
    end

    it 'returns direction as :bullish or :bearish' do
      result = indicator.calculate_at(index)
      expect(result[:direction]).to be_in(%i[bullish bearish])
    end

    it 'returns confidence between 0 and 100' do
      result = indicator.calculate_at(index)
      expect(result[:confidence]).to be_between(0, 100)
    end

    it 'calculates Supertrend once and caches result' do
      expect(Indicators::Supertrend).to receive(:new).once.and_call_original
      indicator.calculate_at(index)
      indicator.calculate_at(index) # Second call should use cache
    end

    context 'with trading hours filter' do
      let(:config) { { period: 7, multiplier: 3.0, trading_hours_filter: true } }

      it 'returns nil for candles outside trading hours' do
        # Create candle outside trading hours
        candle = Candle.new(
          ts: Time.zone.parse('2024-01-01 09:00:00 IST'),
          open: 22_000,
          high: 22_050,
          low: 21_980,
          close: 22_020,
          volume: 1000
        )
        series.add_candle(candle)
        index = series.candles.size - 1

        result = indicator.calculate_at(index)
        expect(result).to be_nil
      end
    end
  end
end
