# frozen_string_literal: true

module Risk
  # Service to determine market condition (bullish/bearish) based on trend analysis
  # Uses TrendScorer and ADX to classify market condition
  class MarketConditionService < ApplicationService
    BULLISH_THRESHOLD = 14.0
    BEARISH_THRESHOLD = 7.0
    MIN_ADX = 20.0

    attr_reader :index_key, :condition, :trend_score, :adx_value

    def initialize(index_key:)
      @index_key = index_key.to_s.upcase
      @condition = nil
      @trend_score = nil
      @adx_value = nil
    end

    def call
      index_cfg = find_index_config
      return default_result unless index_cfg

      instrument = fetch_instrument(index_cfg)
      return default_result unless instrument

      # Get trend score
      trend_result = compute_trend_score(instrument)
      @trend_score = trend_result[:trend_score]

      # Get ADX value
      @adx_value = compute_adx(instrument)

      # Determine condition
      @condition = determine_condition(@trend_score, @adx_value)

      {
        condition: @condition,
        trend_score: @trend_score,
        adx_value: @adx_value,
        condition_name: condition_name(@condition)
      }
    rescue StandardError => e
      Rails.logger.error("[MarketConditionService] Error for #{@index_key}: #{e.class} - #{e.message}")
      default_result
    end

    private

    def find_index_config
      config = AlgoConfig.fetch
      indices = config[:indices] || []
      indices.find { |idx| idx[:key]&.upcase == @index_key }
    rescue StandardError
      nil
    end

    def fetch_instrument(index_cfg)
      IndexInstrumentCache.instance.get_or_fetch(index_cfg)
    rescue StandardError => e
      Rails.logger.debug { "[MarketConditionService] Instrument fetch failed: #{e.message}" }
      nil
    end

    def compute_trend_score(instrument)
      scorer = Signal::TrendScorer.new(
        instrument: instrument,
        primary_tf: '1m',
        confirmation_tf: '5m'
      )
      scorer.compute_trend_score
    rescue StandardError => e
      Rails.logger.debug { "[MarketConditionService] Trend score failed: #{e.message}" }
      { trend_score: nil }
    end

    def compute_adx(instrument)
      series = instrument.candle_series(interval: '1')
      return nil unless series&.candles&.any?

      calculator = Indicators::Calculator.new(series)
      calculator.adx(14)
    rescue StandardError => e
      Rails.logger.debug { "[MarketConditionService] ADX calculation failed: #{e.message}" }
      nil
    end

    def determine_condition(trend_score, adx_value)
      return :neutral unless trend_score&.positive?

      # Require minimum ADX for strong directional bias
      has_trend_strength = adx_value&.positive? && adx_value >= MIN_ADX

      # If ADX is low, still use trend score but mark as neutral if very weak
      if trend_score >= BULLISH_THRESHOLD
        has_trend_strength ? :bullish : :neutral
      elsif trend_score <= BEARISH_THRESHOLD
        has_trend_strength ? :bearish : :neutral
      else
        :neutral
      end
    end

    def condition_name(condition)
      case condition
      when :bullish then 'Bullish'
      when :bearish then 'Bearish'
      else 'Neutral'
      end
    end

    def default_result
      {
        condition: :neutral,
        trend_score: nil,
        adx_value: nil,
        condition_name: 'Neutral'
      }
    end
  end
end
