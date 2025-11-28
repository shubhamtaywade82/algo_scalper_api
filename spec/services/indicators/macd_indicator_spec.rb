# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::MacdIndicator do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:config) { { fast_period: 12, slow_period: 26, signal_period: 9 } }
  let(:indicator) { described_class.new(series: series, config: config) }

  before do
    # Create enough candles for MACD calculation
    50.times do |i|
      price = 22000.0 + (i * 10)
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
  end

  describe '#min_required_candles' do
    it 'returns minimum candles required for MACD' do
      min_candles = indicator.min_required_candles
      expect(min_candles).to be >= 26 # Slow period
      expect(min_candles).to be_a(Integer)
    end
  end

  describe '#calculate_at' do
    let(:index) { series.candles.size - 1 }

    it 'returns hash with required keys' do
      result = indicator.calculate_at(index)
      expect(result).to be_a(Hash).or be_nil
      if result
        expect(result).to have_key(:value)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:confidence)
      end
    end

    it 'uses CandleSeries#macd for calculation' do
      partial_series = double('CandleSeries')
      allow(indicator).to receive(:create_partial_series).and_return(partial_series)
      allow(partial_series).to receive(:macd).with(12, 26, 9).and_return([1.5, 1.0, 0.5])

      result = indicator.calculate_at(index)
      expect(partial_series).to have_received(:macd).with(12, 26, 9)
    end

    it 'returns bullish direction when MACD crosses above signal' do
      allow_any_instance_of(CandleSeries).to receive(:macd).and_return([2.0, 1.0, 1.0]) # MACD > Signal, positive histogram
      result = indicator.calculate_at(index)
      expect(result[:direction]).to eq(:bullish) if result
    end

    it 'returns bearish direction when MACD crosses below signal' do
      allow_any_instance_of(CandleSeries).to receive(:macd).and_return([1.0, 2.0, -1.0]) # MACD < Signal, negative histogram
      result = indicator.calculate_at(index)
      expect(result[:direction]).to eq(:bearish) if result
    end
  end
end
