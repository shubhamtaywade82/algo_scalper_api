# frozen_string_literal: true

# Service for analyzing multiple indices and providing consolidated market view
class MarketAnalyzer < ApplicationService
  DEFAULT_INDICES = %i[nifty sensex].freeze

  # Analyze multiple indices in parallel
  def call(indices: DEFAULT_INDICES, timeframes: IndexTechnicalAnalyzer::DEFAULT_TIMEFRAMES,
           days_back: IndexTechnicalAnalyzer::DEFAULT_DAYS_BACK)
    results = {}

    indices.each do |index|
      analyzer = IndexTechnicalAnalyzer.new(index)
      analysis_result = analyzer.call(timeframes: timeframes, days_back: days_back)

      if analysis_result[:success] && analyzer.success?
        results[index] = analyzer.result
      else
        results[index] = {
          index: index,
          error: analyzer.error || 'Analysis failed',
          signal: :neutral,
          confidence: 0.0
        }
        log_warn("Failed to analyze #{index}: #{analyzer.error}")
      end
    end

    # Generate overall market bias
    results[:overall] = overall_market_bias(results)

    { success: true, results: results }
  rescue StandardError => e
    log_error("Market analysis failed: #{e.class} - #{e.message}")
    { success: false, error: e.message, results: {} }
  end

  # Get the strongest signal across indices
  def self.strongest_signal(results)
    valid_results = results.select { |k, v| k != :overall && v[:signal] && !v[:error] }
    return :neutral if valid_results.empty?

    # Weight by confidence
    signals = valid_results.map do |_index, result|
      { signal: result[:signal], confidence: result[:confidence] }
    end

    # Simple majority voting with confidence weighting
    bullish_score = signals.select { |s| s[:signal] == :bullish }
                           .sum { |s| s[:confidence] }
    bearish_score = signals.select { |s| s[:signal] == :bearish }
                           .sum { |s| s[:confidence] }

    if bullish_score > bearish_score && bullish_score > 0.5
      :bullish
    elsif bearish_score > bullish_score && bearish_score > 0.5
      :bearish
    else
      :neutral
    end
  end

  private

  def overall_market_bias(results)
    signal = self.class.strongest_signal(results)
    matching_results = results.values.select { |r| r[:signal] == signal && !r[:error] }
    confidence = if matching_results.any?
                   matching_results.pluck(:confidence).sum / matching_results.size
                 else
                   0.0
                 end

    {
      signal: signal,
      confidence: confidence,
      timestamp: Time.current,
      indices_analyzed: results.keys.count { |k| k != :overall }
    }
  end
end
