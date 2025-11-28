# frozen_string_literal: true

# Composite strategy that combines multiple indicators
# Supports different confirmation modes: all, majority, weighted, any
class MultiIndicatorStrategy
  CONFIRMATION_MODES = {
    all: :all_must_agree,      # All indicators must agree
    majority: :majority_vote,   # Majority of indicators must agree
    weighted: :weighted_sum,    # Weighted sum of indicator confidences
    any: :any_confirms          # Any indicator can confirm
  }.freeze

  attr_reader :series, :indicators, :confirmation_mode, :min_confidence

  def initialize(series:, indicators: [], confirmation_mode: :all, min_confidence: 60, **config)
    @series = series
    @indicators = build_indicators(indicators, config)
    @confirmation_mode = CONFIRMATION_MODES[confirmation_mode] || :all_must_agree
    @min_confidence = min_confidence
    @config = config
  end

  # Generates entry signal at given candle index
  # Returns: { type: :ce/:pe, confidence: 0-100 } or nil
  def generate_signal(index)
    return nil if indicators.empty?
    return nil unless enough_candles?(index)

    # Calculate all indicators at current index
    indicator_results = calculate_all_indicators(index)
    return nil if indicator_results.empty?

    # Filter out nil results (indicators that couldn't calculate)
    valid_results = indicator_results.compact
    return nil if valid_results.empty?

    # Determine direction based on confirmation mode
    direction = determine_direction(valid_results)
    return nil unless direction

    # Calculate combined confidence
    confidence = calculate_combined_confidence(valid_results, direction)
    return nil if confidence < min_confidence

    { type: direction, confidence: confidence }
  end

  private

  def build_indicators(indicator_configs, global_config)
    indicator_configs.map do |indicator_config|
      build_indicator(indicator_config, global_config)
    end.compact
  end

  def build_indicator(indicator_config, global_config)
    indicator_type = indicator_config[:type] || indicator_config[:name]
    config = global_config.merge(indicator_config[:config] || {})

    case indicator_type.to_s.downcase
    when 'supertrend', 'st'
      Indicators::SupertrendIndicator.new(series: series, config: config)
    when 'adx'
      Indicators::AdxIndicator.new(series: series, config: config)
    when 'rsi'
      Indicators::RsiIndicator.new(series: series, config: config)
    when 'macd'
      Indicators::MacdIndicator.new(series: series, config: config)
    when 'trend_duration', 'trend_duration_forecast', 'tdf'
      Indicators::TrendDurationIndicator.new(series: series, config: config)
    else
      Rails.logger.warn("[MultiIndicatorStrategy] Unknown indicator type: #{indicator_type}")
      nil
    end
  end

  def enough_candles?(index)
    max_required = indicators.map(&:min_required_candles).max || 0
    index >= max_required
  end

  def calculate_all_indicators(index)
    indicators.map do |indicator|
      next nil unless indicator.ready?(index)

      begin
        result = indicator.calculate_at(index)
        result ? { indicator: indicator.name, **result } : nil
      rescue StandardError => e
        Rails.logger.error("[MultiIndicatorStrategy] Error calculating #{indicator.name}: #{e.class} - #{e.message}")
        nil
      end
    end
  end

  def determine_direction(indicator_results)
    case confirmation_mode
    when :all_must_agree
      all_must_agree(indicator_results)
    when :majority_vote
      majority_vote(indicator_results)
    when :weighted_sum
      weighted_sum_direction(indicator_results)
    when :any_confirms
      any_confirms(indicator_results)
    else
      all_must_agree(indicator_results)
    end
  end

  def all_must_agree(results)
    directions = results.map { |r| r[:direction] }.uniq
    return nil if directions.size > 1

    direction = directions.first
    return nil if direction == :neutral

    direction == :bullish ? :ce : :pe
  end

  def majority_vote(results)
    bullish_count = results.count { |r| r[:direction] == :bullish }
    bearish_count = results.count { |r| r[:direction] == :bearish }
    neutral_count = results.count { |r| r[:direction] == :neutral }

    total = results.size
    return nil if bullish_count == bearish_count # Tie

    if bullish_count > bearish_count && bullish_count > neutral_count
      return :ce if bullish_count.to_f / total >= 0.5
    end

    if bearish_count > bullish_count && bearish_count > neutral_count
      return :pe if bearish_count.to_f / total >= 0.5
    end

    nil
  end

  def weighted_sum_direction(results)
    bullish_score = 0.0
    bearish_score = 0.0

    results.each do |result|
      weight = result[:confidence] || 50
      case result[:direction]
      when :bullish
        bullish_score += weight
      when :bearish
        bearish_score += weight
      end
    end

    return nil if bullish_score == bearish_score
    return nil if [bullish_score, bearish_score].max < min_confidence

    bullish_score > bearish_score ? :ce : :pe
  end

  def any_confirms(results)
    # Check if any indicator confirms bullish or bearish
    bullish_results = results.select { |r| r[:direction] == :bullish }
    bearish_results = results.select { |r| r[:direction] == :bearish }

    return :ce if bullish_results.any? && bullish_results.first[:confidence] >= min_confidence
    return :pe if bearish_results.any? && bearish_results.first[:confidence] >= min_confidence

    nil
  end

  def calculate_combined_confidence(results, direction)
    case confirmation_mode
    when :weighted_sum
      calculate_weighted_confidence(results, direction)
    when :all_must_agree
      calculate_average_confidence(results, direction)
    when :majority_vote
      calculate_majority_confidence(results, direction)
    when :any_confirms
      calculate_max_confidence(results, direction)
    else
      calculate_average_confidence(results, direction)
    end
  end

  def calculate_weighted_confidence(results, direction)
    matching_results = results.select { |r| r[:direction] == (direction == :ce ? :bullish : :bearish) }
    return 0 if matching_results.empty?

    total_weight = matching_results.sum { |r| r[:confidence] || 0 }
    count = matching_results.size
    (total_weight / count).round
  end

  def calculate_average_confidence(results, direction)
    matching_results = results.select { |r| r[:direction] == (direction == :ce ? :bullish : :bearish) }
    return 0 if matching_results.empty?

    total = matching_results.sum { |r| r[:confidence] || 0 }
    (total / matching_results.size).round
  end

  def calculate_majority_confidence(results, direction)
    matching_results = results.select { |r| r[:direction] == (direction == :ce ? :bullish : :bearish) }
    return 0 if matching_results.empty?

    # Average confidence of majority indicators
    total = matching_results.sum { |r| r[:confidence] || 0 }
    (total / matching_results.size).round
  end

  def calculate_max_confidence(results, direction)
    matching_results = results.select { |r| r[:direction] == (direction == :ce ? :bullish : :bearish) }
    return 0 if matching_results.empty?

    matching_results.map { |r| r[:confidence] || 0 }.max
  end
end
