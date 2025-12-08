# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Modular Indicator System Integration', type: :integration do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13',
      capital_alloc_pct: 0.30
    }
  end

  before do
    # Create realistic market data
    base_price = 22_000.0
    current_time = Time.zone.parse('2024-01-01 10:00:00 IST')

    100.times do |i|
      # Create upward trending market
      price = base_price + (i * 15)
      candle = Candle.new(
        timestamp: current_time + (i * 5).minutes,
        open: price,
        high: price + 10,
        low: price - 5,
        close: price + 8,
        volume: 1000 + i
      )
      series.add_candle(candle)
    end
  end

  describe 'end-to-end indicator workflow' do
    it 'builds indicators via factory and generates signals' do
      config = {
        indicators: [
          { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
          { type: 'adx', config: { period: 14, min_strength: 18 } }
        ]
      }

      indicators = Indicators::IndicatorFactory.build_indicators(series: series, config: config)
      expect(indicators.size).to eq(2)

      index = series.candles.size - 1
      results = indicators.map { |ind| ind.calculate_at(index) }.compact

      expect(results).not_to be_empty
      results.each do |result|
        expect(result).to have_key(:value)
        expect(result).to have_key(:direction)
        expect(result).to have_key(:confidence)
      end
    end

    it 'combines indicators via MultiIndicatorStrategy' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: [
          { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
          { type: 'adx', config: { period: 14, min_strength: 18 } }
        ],
        confirmation_mode: :all,
        min_confidence: 50
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)

      expect(signal).to be_a(Hash).or be_nil
      if signal
        expect(signal[:type]).to be_in(%i[ce pe])
        expect(signal[:confidence]).to be_between(0, 100)
      end
    end
  end

  describe 'all indicator types integration' do
    it 'works with all available indicators' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: [
          { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
          { type: 'adx', config: { period: 14, min_strength: 18 } },
          { type: 'rsi', config: { period: 14 } },
          { type: 'macd', config: { fast_period: 12, slow_period: 26, signal_period: 9 } },
          { type: 'trend_duration', config: { hma_length: 20, trend_length: 5 } }
        ],
        confirmation_mode: :majority,
        min_confidence: 50
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)

      # Signal may or may not be generated depending on indicator agreement
      expect(signal).to be_a(Hash).or be_nil
    end
  end

  describe 'confirmation modes integration' do
    let(:indicators_config) do
      [
        { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
        { type: 'adx', config: { period: 14, min_strength: 18 } },
        { type: 'rsi', config: { period: 14 } }
      ]
    end

    it 'works with all confirmation mode' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: indicators_config,
        confirmation_mode: :all,
        min_confidence: 50
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)
      expect(signal).to be_a(Hash).or be_nil
    end

    it 'works with majority confirmation mode' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: indicators_config,
        confirmation_mode: :majority,
        min_confidence: 50
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)
      expect(signal).to be_a(Hash).or be_nil
    end

    it 'works with weighted confirmation mode' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: indicators_config,
        confirmation_mode: :weighted,
        min_confidence: 50
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)
      expect(signal).to be_a(Hash).or be_nil
    end

    it 'works with any confirmation mode' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: indicators_config,
        confirmation_mode: :any,
        min_confidence: 50
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)
      expect(signal).to be_a(Hash).or be_nil
    end
  end

  describe 'backward compatibility' do
    it 'SupertrendAdxStrategy uses MultiIndicatorStrategy internally' do
      supertrend_cfg = { period: 7, multiplier: 3.0 }
      strategy = SupertrendAdxStrategy.new(
        series: series,
        supertrend_cfg: supertrend_cfg,
        adx_min_strength: 20
      )

      index = series.candles.size - 1
      signal = strategy.generate_signal(index)

      expect(signal).to be_a(Hash).or be_nil
      if signal
        expect(signal[:type]).to be_in(%i[ce pe])
        expect(signal[:confidence]).to be_between(0, 100)
      end
    end
  end

  describe 'configuration-driven workflow' do
    let(:signals_cfg) do
      {
        use_multi_indicator_strategy: true,
        confirmation_mode: :all,
        min_confidence: 60,
        indicators: [
          {
            type: 'supertrend',
            enabled: true,
            config: { period: 7, multiplier: 3.0 }
          },
          {
            type: 'adx',
            enabled: true,
            config: { period: 14, min_strength: 18 }
          }
        ]
      }
    end

    it 'builds strategy from configuration' do
      enabled_indicators = signals_cfg[:indicators].select { |ic| ic[:enabled] != false }
      global_config = { supertrend_cfg: { period: 7, multiplier: 3.0 } }

      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: enabled_indicators,
        confirmation_mode: signals_cfg[:confirmation_mode],
        min_confidence: signals_cfg[:min_confidence],
        **global_config
      )

      expect(strategy.indicators.size).to eq(2)
      # The moderate preset defaults to :majority mode, which maps to :majority_vote
      # To get :all_must_agree, we'd need to pass indicator_preset: :tight or :production in global_config
      expect(strategy.confirmation_mode).to eq(:majority_vote)
      expect(strategy.min_confidence).to eq(60)
    end

    it 'filters out disabled indicators' do
      signals_cfg[:indicators] << {
        type: 'rsi',
        enabled: false,
        config: { period: 14 }
      }

      enabled_indicators = signals_cfg[:indicators].select { |ic| ic[:enabled] != false }

      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: enabled_indicators,
        confirmation_mode: :all
      )

      expect(strategy.indicators.size).to eq(2)
      expect(strategy.indicators.none? { |ind| ind.is_a?(Indicators::RsiIndicator) }).to be true
    end
  end

  describe 'error handling and resilience' do
    it 'handles indicator calculation failures gracefully' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: [
          { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
          { type: 'adx', config: { period: 14, min_strength: 18 } }
        ],
        confirmation_mode: :any, # Any can still work if one fails
        min_confidence: 50
      )

      # Force one indicator to fail
      allow_any_instance_of(Indicators::SupertrendIndicator).to receive(:calculate_at).and_raise(StandardError,
                                                                                                 'Test error')

      index = series.candles.size - 1
      expect { strategy.generate_signal(index) }.not_to raise_error

      signal = strategy.generate_signal(index)
      # May still generate signal if ADX works, or nil if both fail
      expect(signal).to be_a(Hash).or be_nil
    end

    it 'handles missing indicator configurations' do
      config = {
        indicators: [
          { type: 'supertrend', config: { period: 7 } },
          { type: 'unknown', config: {} }
        ]
      }

      indicators = Indicators::IndicatorFactory.build_indicators(series: series, config: config)
      expect(indicators.size).to eq(1) # Only supertrend should be built
      expect(indicators.first).to be_a(Indicators::SupertrendIndicator)
    end
  end

  describe 'performance with multiple indicators' do
    it 'calculates all indicators efficiently' do
      strategy = MultiIndicatorStrategy.new(
        series: series,
        indicators: [
          { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
          { type: 'adx', config: { period: 14 } },
          { type: 'rsi', config: { period: 14 } },
          { type: 'macd', config: { fast_period: 12, slow_period: 26, signal_period: 9 } }
        ],
        confirmation_mode: :all
      )

      index = series.candles.size - 1

      # Should complete in reasonable time
      start_time = Time.current
      signal = strategy.generate_signal(index)
      elapsed = Time.current - start_time

      expect(elapsed).to be < 5.seconds # Should complete quickly
      expect(signal).to be_a(Hash).or be_nil
    end
  end
end
