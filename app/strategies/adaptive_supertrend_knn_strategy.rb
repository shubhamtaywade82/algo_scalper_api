# frozen_string_literal: true

# Adaptive Supertrend + KNN Classifier Strategy
# Combines ML Adaptive Volatility Supertrend with K-Nearest Neighbors pattern classification
# for high-probability options derivative entry signals.
class AdaptiveSupertrendKnnStrategy
  attr_reader :series, :k_neighbors, :min_confidence, :adaptive_st_config

  def initialize(series:, k_neighbors: 5, min_confidence: 60, adaptive_st_config: {})
    @series = series
    @k_neighbors = k_neighbors
    @min_confidence = min_confidence
    @adaptive_st_config = adaptive_st_config
  end

  # Generates entry signal for current candle series
  # @param index [Integer] Index in candles array to evaluate (defaults to last bar)
  # @return [Hash, nil] Signal hash or nil
  def generate_signal(index = -1)
    candles = extract_candles
    return nil if candles.blank? || candles.size < 30

    eval_idx = index.negative? ? candles.size + index : index
    return nil if eval_idx < 15 || eval_idx >= candles.size

    st_result = compute_adaptive_supertrend
    st_dir = st_result[:direction][eval_idx]
    return nil if st_dir.nil?

    knn_probs = predict_knn_probabilities(eval_idx)

    build_signal_outcome(st_dir, knn_probs, st_result, eval_idx)
  end

  private

  def extract_candles
    return series.candles if series.respond_to?(:candles)
    series.is_a?(Array) ? series : []
  end

  def compute_adaptive_supertrend
    candles = extract_candles
    effective_config = adaptive_st_config.dup
    if effective_config[:training_period].blank? && candles.size < 100
      effective_config[:training_period] = [candles.size / 2, 5].max
    end
    Indicators::MlAdaptiveSupertrend.new(series: series, config: effective_config).call
  end

  def build_signal_outcome(st_dir, knn_probs, st_result, eval_idx)
    is_bullish = st_dir == -1
    confidence = is_bullish ? knn_probs[:bullish] : knn_probs[:bearish]

    return nil if confidence < min_confidence

    action_type = is_bullish ? :buy_call : :buy_put
    direction_sym = is_bullish ? :bullish : :bearish

    {
      action: action_type,
      type: is_bullish ? :ce : :pe,
      direction: direction_sym,
      confidence: confidence.round(2),
      supertrend_value: st_result[:super_trend][eval_idx],
      regime: st_result[:regimes][eval_idx],
      knn_probabilities: knn_probs
    }
  end

  # Feature extraction for KNN classification:
  # Vector = [RSI/100, ADX/100, Normalized_ATR, Intraday_Momentum]
  def extract_feature_at(idx)
    rsi = fetch_indicator_val(:rsi, 14, idx) || 50.0
    adx = fetch_indicator_val(:adx, 14, idx) || 20.0
    atr = fetch_indicator_val(:atr, 14, idx) || 1.0
    candles = extract_candles
    close = candles[idx]&.close.to_f
    open_val = candles[idx]&.open.to_f

    mom = open_val.positive? ? (close - open_val) / open_val : 0.0
    atr_ratio = close.positive? ? atr / close : 0.0

    [rsi / 100.0, adx / 100.0, atr_ratio * 100.0, mom * 10.0]
  end

  def fetch_indicator_val(indicator, period, idx)
    if series.respond_to?(indicator)
      res = series.send(indicator, period)
      res.is_a?(Array) ? res[idx] : res
    end
  rescue StandardError
    nil
  end

  # KNN Nearest Neighbors classification over past historical window
  def predict_knn_probabilities(eval_idx)
    target_vector = extract_feature_at(eval_idx)
    historical_window = (15...(eval_idx - 1)).to_a
    return { bullish: 50.0, bearish: 50.0 } if historical_window.empty?

    distances = calculate_distances(target_vector, historical_window)
    k_nearest = distances.sort_by { |d| d[:dist] }.first(k_neighbors)

    tally_knn_votes(k_nearest)
  end

  def calculate_distances(target_vector, window_indices)
    candles = extract_candles
    window_indices.filter_map do |h_idx|
      h_vector = extract_feature_at(h_idx)
      next_close = candles[h_idx + 1]&.close.to_f
      curr_close = candles[h_idx]&.close.to_f
      outcome_bullish = next_close > curr_close

      dist = euclidean_distance(target_vector, h_vector)
      { dist: dist, outcome_bullish: outcome_bullish }
    end
  end

  def euclidean_distance(v1, v2)
    sum_sq = v1.zip(v2).sum { |a, b| (a.to_f - b.to_f)**2 }
    Math.sqrt(sum_sq)
  end

  def tally_knn_votes(k_nearest)
    return { bullish: 50.0, bearish: 50.0 } if k_nearest.empty?

    bullish_votes = k_nearest.count { |item| item[:outcome_bullish] }
    bullish_pct = (bullish_votes.to_f / k_nearest.size) * 100.0
    bearish_pct = 100.0 - bullish_pct

    { bullish: bullish_pct, bearish: bearish_pct }
  end
end
