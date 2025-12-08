# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::AdxIndicator do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:config) { { period: 14, min_strength: 20 } }
  let(:indicator) { described_class.new(series: series, config: config) }

  before do
    # Create enough candles for ADX calculation
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

    it 'uses default config when not provided' do
      indicator_default = described_class.new(series: series)
      expect(indicator_default.config).to eq({})
    end
  end

  describe '#min_required_candles' do
    it 'returns minimum candles required for ADX' do
      min_candles = indicator.min_required_candles
      expect(min_candles).to be >= 14 # ADX period
      expect(min_candles).to be_a(Integer)
    end
  end

  describe '#ready?' do
    it 'returns false when not enough candles' do
      expect(indicator.ready?(10)).to be false
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

    it 'uses CandleSeries#adx for calculation' do
      partial_series = double('CandleSeries')
      allow(indicator).to receive(:create_partial_series).and_return(partial_series)
      allow(partial_series).to receive(:adx).with(14).and_return(25.0)

      result = indicator.calculate_at(index)
      expect(partial_series).to have_received(:adx).with(14)
    end

    it 'returns direction based on price movement' do
      result = indicator.calculate_at(index)
      expect(result[:direction]).to be_in([:bullish, :bearish])
    end

    it 'returns confidence based on ADX strength' do
      result = indicator.calculate_at(index)
      expect(result[:confidence]).to be_between(0, 100)
    end

    it 'filters weak ADX values below min_strength' do
      # Stub ThresholdConfig to return the test config (min_strength: 20) instead of preset
      allow(Indicators::ThresholdConfig).to receive(:merge_with_thresholds).and_return(config)

      # Stub the create_partial_series method to return a series with stubbed adx
      partial_series = double('CandleSeries')
      allow(indicator).to receive(:create_partial_series).and_return(partial_series)
      allow(partial_series).to receive(:adx).with(14).and_return(15.0) # Below min_strength of 20
      result = indicator.calculate_at(index)
      expect(result).to be_nil
    end
  end
end
