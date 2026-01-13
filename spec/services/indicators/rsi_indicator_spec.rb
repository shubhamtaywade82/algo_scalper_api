# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::RsiIndicator do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:config) { { period: 14 } }
  let(:indicator) { described_class.new(series: series, config: config) }

  before do
    # Create enough candles for RSI calculation
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
  end

  describe '#min_required_candles' do
    it 'returns minimum candles required for RSI' do
      min_candles = indicator.min_required_candles
      expect(min_candles).to be >= 14 # RSI period
      expect(min_candles).to be_a(Integer)
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

    it 'uses CandleSeries#rsi for calculation' do
      partial_series = double('CandleSeries')
      allow(indicator).to receive(:create_partial_series).and_return(partial_series)
      allow(partial_series).to receive(:rsi).with(14).and_return(65.0)

      indicator.calculate_at(index)
      expect(partial_series).to have_received(:rsi).with(14)
    end

    it 'returns bullish direction for oversold RSI' do
      allow_any_instance_of(CandleSeries).to receive(:rsi).and_return(25.0) # Oversold
      result = indicator.calculate_at(index)
      expect(result[:direction]).to eq(:bullish)
    end

    it 'returns bearish direction for overbought RSI' do
      allow_any_instance_of(CandleSeries).to receive(:rsi).and_return(75.0) # Overbought
      result = indicator.calculate_at(index)
      expect(result[:direction]).to eq(:bearish)
    end

    it 'returns nil for neutral RSI' do
      allow_any_instance_of(CandleSeries).to receive(:rsi).and_return(50.0) # Neutral
      result = indicator.calculate_at(index)
      expect(result).to be_nil
    end
  end
end
