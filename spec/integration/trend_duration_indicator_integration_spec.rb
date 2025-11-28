# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trend Duration Indicator Integration', type: :integration do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }

  describe 'end-to-end trend duration calculation' do
    before do
      # Create realistic market data with trend changes
      base_price = 22000.0
      current_time = Time.zone.parse('2024-01-01 10:00:00 IST')

      # Phase 1: Bullish trend (20 bars)
      20.times do |i|
        price = base_price + (i * 15)
        candle = Candle.new(
          ts: current_time + (i * 5).minutes,
          open: price,
          high: price + 10,
          low: price - 5,
          close: price + 8,
          volume: 1000 + i
        )
        series.add_candle(candle)
      end

      # Phase 2: Bearish trend (15 bars)
      base_price = series.candles.last.close
      15.times do |i|
        price = base_price - (i * 12)
        candle = Candle.new(
          ts: current_time + ((20 + i) * 5).minutes,
          open: price,
          high: price + 5,
          low: price - 10,
          close: price - 8,
          volume: 1000 + i
        )
        series.add_candle(candle)
      end

      # Phase 3: Bullish trend again (10 bars)
      base_price = series.candles.last.close
      10.times do |i|
        price = base_price + (i * 18)
        candle = Candle.new(
          ts: current_time + ((35 + i) * 5).minutes,
          open: price,
          high: price + 12,
          low: price - 3,
          close: price + 10,
          volume: 1000 + i
        )
        series.add_candle(candle)
      end
    end

    it 'tracks multiple trend changes correctly' do
      indicator = Indicators::TrendDurationIndicator.new(
        series: series,
        config: { hma_length: 20, trend_length: 5, samples: 10 }
      )

      # Calculate at different points to see trend evolution
      results = []
      min_candles = indicator.min_required_candles

      (min_candles..series.candles.size - 1).each do |index|
        result = indicator.calculate_at(index)
        results << result if result
      end

      expect(results).not_to be_empty

      # Should have detected trends
      trends = results.map { |r| r[:value][:trend_direction] }.compact.uniq
      expect(trends).to include(:bullish, :bearish)
    end

    it 'calculates probable durations based on history' do
      indicator = Indicators::TrendDurationIndicator.new(
        series: series,
        config: { hma_length: 20, trend_length: 5, samples: 10 }
      )

      # Process all candles to build history
      min_candles = indicator.min_required_candles
      (min_candles..series.candles.size - 1).each do |index|
        indicator.calculate_at(index)
      end

      # Final calculation should have probable duration
      final_result = indicator.calculate_at(series.candles.size - 1)
      expect(final_result).not_to be_nil
      expect(final_result[:value][:probable_length]).to be_a(Numeric)
      expect(final_result[:value][:probable_length]).to be > 0
    end
  end

  describe 'integration with MultiIndicatorStrategy' do
    before do
      base_price = 22000.0
      min_candles = 50 # Enough for trend duration indicator

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
    end

    it 'works with MultiIndicatorStrategy' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: [
          {
            type: 'trend_duration',
            config: {
              hma_length: 20,
              trend_length: 5,
              samples: 10
            }
          }
        ],
        confirmation_mode: :all,
        min_confidence: 50
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)

      expect(signal).to be_a(Hash).or be_nil
      if signal
        expect(signal).to have_key(:type)
        expect(signal).to have_key(:confidence)
        expect(signal[:type]).to be_in([:ce, :pe])
        expect(signal[:confidence]).to be_between(0, 100)
      end
    end

    it 'combines with other indicators' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: [
          {
            type: 'supertrend',
            config: { period: 7, multiplier: 3.0 }
          },
          {
            type: 'trend_duration',
            config: {
              hma_length: 20,
              trend_length: 5,
              samples: 10
            }
          }
        ],
        confirmation_mode: :all,
        min_confidence: 60
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)

      # Signal may or may not be generated depending on indicator agreement
      expect(signal).to be_a(Hash).or be_nil
    end
  end

  describe 'real-world scenario: trend continuation signal' do
    before do
      # Simulate a strong bullish trend
      base_price = 22000.0
      min_candles = 50

      min_candles.times do |i|
        # Strong upward momentum
        price = base_price + (i * 25)
        candle = Candle.new(
          ts: Time.zone.parse('2024-01-01 10:00:00 IST') + i.minutes,
          open: price,
          high: price + 15,
          low: price - 5,
          close: price + 12,
          volume: 2000 + (i * 10)
        )
        series.add_candle(candle)
      end
    end

    it 'generates high confidence signal for strong trends' do
      indicator = Indicators::TrendDurationIndicator.new(
        series: series,
        config: { hma_length: 20, trend_length: 5, samples: 10 }
      )

      index = series.candles.size - 1
      result = indicator.calculate_at(index)

      expect(result).not_to be_nil
      expect(result[:confidence]).to be >= 50

      # Strong trend should have high confidence
      if result[:value][:real_length] >= 10
        expect(result[:confidence]).to be >= 60
      end
    end

    it 'provides actionable signal data' do
      indicator = Indicators::TrendDurationIndicator.new(
        series: series,
        config: { hma_length: 20, trend_length: 5, samples: 10 }
      )

      index = series.candles.size - 1
      result = indicator.calculate_at(index)

      expect(result).not_to be_nil

      # Signal should contain all necessary information
      expect(result[:value][:hma]).to be_a(Numeric)
      expect(result[:value][:trend_direction]).to be_in([:bullish, :bearish])
      expect(result[:value][:real_length]).to be_a(Integer)
      expect(result[:value][:probable_length]).to be_a(Numeric)
      expect(result[:value][:slope]).to be_in(['up', 'down'])

      # Can be used for options trading decisions
      if result[:direction] == :bullish && result[:confidence] >= 60
        # Signal: Buy CE options
        expect(result[:value][:trend_direction]).to eq(:bullish)
      end
    end
  end
end
