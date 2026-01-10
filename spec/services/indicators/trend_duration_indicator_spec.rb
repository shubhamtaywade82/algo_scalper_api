# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::TrendDurationIndicator, type: :service do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:config) { { hma_length: 20, trend_length: 5, samples: 10 } }
  let(:indicator) { described_class.new(series: series, config: config) }

  describe '#initialize' do
    it 'initializes with default config' do
      indicator_default = described_class.new(series: series)
      expect(indicator_default.instance_variable_get(:@hma_length)).to eq(20)
      expect(indicator_default.instance_variable_get(:@trend_length)).to eq(5)
      expect(indicator_default.instance_variable_get(:@samples)).to eq(10)
    end

    it 'initializes with custom config' do
      custom_config = { hma_length: 14, trend_length: 3, samples: 5 }
      indicator_custom = described_class.new(series: series, config: custom_config)
      expect(indicator_custom.instance_variable_get(:@hma_length)).to eq(14)
      expect(indicator_custom.instance_variable_get(:@trend_length)).to eq(3)
      expect(indicator_custom.instance_variable_get(:@samples)).to eq(5)
    end
  end

  describe '#min_required_candles' do
    it 'returns correct minimum candles for HMA calculation' do
      min_candles = indicator.min_required_candles
      expect(min_candles).to be > 20 # Should be more than hma_length
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
      expect(indicator.ready?(min_candles + 10)).to be true
    end
  end

  describe '#calculate_at' do
    before do
      # Create enough candles for HMA calculation and trend detection
      min_candles = indicator.min_required_candles
      trend_length = config[:trend_length] || 5
      # Need min_candles + trend_length to have enough HMA values for trend detection
      total_candles = min_candles + trend_length + 5 # Extra buffer
      base_price = 22_000.0

      total_candles.times do |i|
        # Create upward trending candles
        price = base_price + (i * 10)
        candle = Candle.new(
          ts: Time.zone.now + i.minutes,
          open: price,
          high: price + 5,
          low: price - 5,
          close: price + 2,
          volume: 1000
        )
        series.add_candle(candle)
      end
    end

    context 'with insufficient data' do
      it 'returns nil when index is too small' do
        result = indicator.calculate_at(5)
        expect(result).to be_nil
      end
    end

    context 'with sufficient data' do
      let(:index) { series.candles.size - 1 }

      it 'returns hash with required keys' do
        result = indicator.calculate_at(index)
        expect(result).to be_a(Hash)
        expect(result).to have_key(:value)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:confidence)
      end

      it 'returns value hash with trend information' do
        result = indicator.calculate_at(index)
        expect(result[:value]).to be_a(Hash)
        expect(result[:value]).to have_key(:hma)
        expect(result[:value]).to have_key(:trend_direction)
        expect(result[:value]).to have_key(:real_length)
        expect(result[:value]).to have_key(:probable_length)
        expect(result[:value]).to have_key(:slope)
      end

      it 'returns direction as :bullish or :bearish' do
        result = indicator.calculate_at(index)
        expect(result[:direction]).to be_in(%i[bullish bearish])
      end

      it 'returns confidence between 0 and 100' do
        result = indicator.calculate_at(index)
        expect(result[:confidence]).to be_between(0, 100)
      end
    end

    context 'with trading hours filter' do
      let(:config_with_filter) { config.merge(trading_hours_filter: true) }
      let(:indicator_filtered) { described_class.new(series: series, config: config_with_filter) }

      before do
        min_candles = indicator_filtered.min_required_candles
        base_price = 22_000.0

        min_candles.times do |i|
          # Create candles outside trading hours (9 AM)
          candle_time = Time.zone.parse('2024-01-01 09:00:00 IST') + i.minutes
          price = base_price + (i * 10)
          candle = Candle.new(
            ts: candle_time,
            open: price,
            high: price + 5,
            low: price - 5,
            close: price + 2,
            volume: 1000
          )
          series.add_candle(candle)
        end
      end

      it 'returns nil for candles outside trading hours' do
        index = series.candles.size - 1
        result = indicator_filtered.calculate_at(index)
        # Should return nil if outside 10 AM - 2:30 PM IST
        expect(result).to be_nil
      end
    end
  end

  describe 'HMA calculation' do
    before do
      # Create test data
      min_candles = indicator.min_required_candles
      base_price = 22_000.0

      min_candles.times do |i|
        price = base_price + (i * 10)
        candle = Candle.new(
          ts: Time.zone.now + i.minutes,
          open: price,
          high: price + 5,
          low: price - 5,
          close: price + 2,
          volume: 1000
        )
        series.add_candle(candle)
      end
    end

    it 'calculates HMA values correctly' do
      # Ensure we have enough candles for HMA calculation
      min_candles = indicator.min_required_candles
      trend_length = config[:trend_length] || 5
      total_needed = min_candles + trend_length + 5

      # Add more candles if needed
      while series.candles.size < total_needed
        i = series.candles.size
        price = 22_000.0 + (i * 10)
        candle = Candle.new(
          ts: Time.zone.now + i.minutes,
          open: price,
          high: price + 5,
          low: price - 5,
          close: price + 2,
          volume: 1000
        )
        series.add_candle(candle)
      end

      index = series.candles.size - 1
      result = indicator.calculate_at(index)
      expect(result).not_to be_nil
      expect(result[:value][:hma]).to be_a(Numeric)
      expect(result[:value][:hma]).to be > 0
    end
  end

  describe 'trend detection' do
    context 'with rising trend' do
      before do
        min_candles = indicator.min_required_candles
        trend_length = config[:trend_length] || 5
        total_needed = min_candles + trend_length + 5
        base_price = 22_000.0

        total_needed.times do |i|
          # Strong upward trend
          price = base_price + (i * 20)
          candle = Candle.new(
            ts: Time.zone.parse('2024-01-01 10:00:00 IST') + i.minutes,
            open: price,
            high: price + 10,
            low: price - 5,
            close: price + 8,
            volume: 1000
          )
          series.add_candle(candle)
        end
      end

      it 'detects bullish trend' do
        index = series.candles.size - 1
        result = indicator.calculate_at(index)
        expect(result).not_to be_nil
        expect(result[:value][:trend_direction]).to eq(:bullish)
        expect(result[:direction]).to eq(:bullish)
        expect(result[:value][:slope]).to eq('up')
      end
    end

    context 'with falling trend' do
      before do
        min_candles = indicator.min_required_candles
        trend_length = config[:trend_length] || 5
        total_needed = min_candles + trend_length + 5
        base_price = 22_000.0

        total_needed.times do |i|
          # Strong downward trend
          price = base_price - (i * 20)
          candle = Candle.new(
            ts: Time.zone.parse('2024-01-01 10:00:00 IST') + i.minutes,
            open: price,
            high: price + 5,
            low: price - 10,
            close: price - 8,
            volume: 1000
          )
          series.add_candle(candle)
        end
      end

      it 'detects bearish trend' do
        index = series.candles.size - 1
        result = indicator.calculate_at(index)
        expect(result).not_to be_nil
        expect(result[:value][:trend_direction]).to eq(:bearish)
        expect(result[:direction]).to eq(:bearish)
        expect(result[:value][:slope]).to eq('down')
      end
    end
  end

  describe 'trend duration tracking' do
    before do
      indicator.min_required_candles
      base_price = 22_000.0

      # Create initial bullish trend
      min_candles = indicator.min_required_candles
      trend_length = config[:trend_length] || 5
      total_needed = min_candles + trend_length + 5

      total_needed.times do |i|
        price = base_price + (i * 10)
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

    it 'tracks trend duration' do
      index = series.candles.size - 1
      result = indicator.calculate_at(index)
      expect(result).not_to be_nil
      expect(result[:value][:real_length]).to be_a(Integer)
      expect(result[:value][:real_length]).to be >= 0
    end

    it 'calculates probable duration' do
      index = series.candles.size - 1
      result = indicator.calculate_at(index)
      expect(result).not_to be_nil
      expect(result[:value][:probable_length]).to be_a(Numeric)
      expect(result[:value][:probable_length]).to be >= 0
    end
  end

  describe 'integration with IndicatorFactory' do
    it 'can be created via IndicatorFactory' do
      indicator_config = {
        type: 'trend_duration',
        config: { hma_length: 20, trend_length: 5 }
      }
      created = Indicators::IndicatorFactory.build_indicator(
        series: series,
        config: indicator_config,
        global_config: {}
      )
      expect(created).to be_a(described_class)
    end
  end

  describe 'edge cases' do
    it 'handles empty series gracefully' do
      empty_series = CandleSeries.new(symbol: symbol, interval: interval)
      empty_indicator = described_class.new(series: empty_series, config: config)
      expect(empty_indicator.ready?(0)).to be false
      expect(empty_indicator.calculate_at(0)).to be_nil
    end

    it 'handles nil values gracefully' do
      min_candles = indicator.min_required_candles
      base_price = 22_000.0

      min_candles.times do |i|
        price = base_price + (i * 10)
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

      # Should not raise error even if some calculations return nil
      index = series.candles.size - 1
      expect { indicator.calculate_at(index) }.not_to raise_error
    end
  end
end
