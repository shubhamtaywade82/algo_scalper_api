# frozen_string_literal: true

# Adaptive Supertrend + KNN — ML adaptive volatility Supertrend filtered by
# K-Nearest-Neighbors pattern classification. Adapted from the backtest
# implementation (app/strategies/adaptive_supertrend_knn_strategy.rb) to the
# platform plugin contract (call(context) -> Signals::*).
class AdaptiveSupertrendKnn < Strategies::Base
  class << self
    def timeframes = %w[1m]
    def instruments = %w[NIFTY BANKNIFTY SENSEX]
    def params_schema
      {
        k_neighbors: { type: "integer", default: 5 },
        min_confidence: { type: "integer", default: 60 }
      }
    end
  end

  def call(context)
    series = context.candles.call("1m")
    return Signals::Hold.new(reason: "no_candle_data") unless series&.candles&.any?

    candles = series.candles
    return Signals::Hold.new(reason: "insufficient_candles") if candles.size < 30

    st_result = compute_adaptive_supertrend(series, candles)
    eval_idx = candles.size - 1
    st_dir = st_result[:direction][eval_idx]
    return Signals::Hold.new(reason: "supertrend_unavailable") if st_dir.nil?

    knn_probs = predict_knn_probabilities(series, candles, eval_idx)
    is_bullish = st_dir == -1
    confidence_pct = is_bullish ? knn_probs[:bullish] : knn_probs[:bearish]
    if confidence_pct < params[:min_confidence]
      return Signals::Hold.new(reason: "confidence_below_min(#{confidence_pct.round(1)})")
    end

    confidence = (confidence_pct / 100.0).clamp(0.0, 1.0)
    if is_bullish
      Signals::BuyCall.new(confidence: confidence,
                           reason: "adaptive_st_bullish_knn_#{confidence_pct.round(0)}")
    else
      Signals::BuyPut.new(confidence: confidence,
                          reason: "adaptive_st_bearish_knn_#{confidence_pct.round(0)}")
    end
  end

  private

  def compute_adaptive_supertrend(series, candles)
    config = {}
    config[:training_period] = [candles.size / 2, 5].max if candles.size < 100
    Indicators::MlAdaptiveSupertrend.new(series: series, config: config).call
  end

  def predict_knn_probabilities(series, candles, eval_idx)
    target_vector = extract_feature_at(series, candles, eval_idx)
    window = (15...(eval_idx - 1)).to_a
    return { bullish: 50.0, bearish: 50.0 } if window.empty?

    distances = window.filter_map do |h_idx|
      h_vector = extract_feature_at(series, candles, h_idx)
      outcome_bullish = candles[h_idx + 1]&.close.to_f > candles[h_idx]&.close.to_f
      { dist: euclidean_distance(target_vector, h_vector), outcome_bullish: outcome_bullish }
    end

    k_nearest = distances.sort_by { |d| d[:dist] }.first(params[:k_neighbors])
    return { bullish: 50.0, bearish: 50.0 } if k_nearest.empty?

    bullish_votes = k_nearest.count { |item| item[:outcome_bullish] }
    bullish_pct = (bullish_votes.to_f / k_nearest.size) * 100.0
    { bullish: bullish_pct, bearish: 100.0 - bullish_pct }
  end

  # Feature vector = [RSI/100, ADX/100, Normalized_ATR, Intraday_Momentum]
  def extract_feature_at(series, candles, idx)
    rsi = fetch_indicator_val(series, :rsi, 14, idx) || 50.0
    adx = fetch_indicator_val(series, :adx, 14, idx) || 20.0
    atr = fetch_indicator_val(series, :atr, 14, idx) || 1.0
    close = candles[idx]&.close.to_f
    open_val = candles[idx]&.open.to_f

    mom = open_val.positive? ? (close - open_val) / open_val : 0.0
    atr_ratio = close.positive? ? atr / close : 0.0

    [rsi / 100.0, adx / 100.0, atr_ratio * 100.0, mom * 10.0]
  end

  def fetch_indicator_val(series, indicator, period, idx)
    res = series.send(indicator, period)
    res.is_a?(Array) ? res[idx] : res
  rescue StandardError
    nil
  end

  def euclidean_distance(v1, v2)
    sum_sq = v1.zip(v2).sum { |a, b| (a.to_f - b.to_f)**2 }
    Math.sqrt(sum_sq)
  end
end
