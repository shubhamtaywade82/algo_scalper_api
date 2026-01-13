# frozen_string_literal: true

module Indicators
  # Adaptive Supertrend indicator with volatility-aware optimisation.
  # Dynamically adjusts the ATR multiplier using a lightweight clustering approach.
  class Supertrend < ApplicationService
    DEFAULT_MULTIPLIER_CANDIDATES = [1.5, 2.0, 2.5, 3.0, 3.5].freeze
    MAX_KMEANS_ITERATIONS = 20

    attr_reader :series, :period, :base_multiplier, :training_period, :num_clusters,
                :performance_alpha, :multiplier_candidates, :performance_scores,
                :adaptive_multipliers, :atr_values

    def initialize(series:, period: 10, base_multiplier: 2.0, training_period: 50,
                   num_clusters: 3, performance_alpha: 0.1, multiplier_candidates: DEFAULT_MULTIPLIER_CANDIDATES)
      @series = series
      @period = period
      @base_multiplier = base_multiplier.to_f
      @training_period = training_period
      @num_clusters = [num_clusters.to_i, 1].max
      @performance_alpha = performance_alpha.to_f
      @multiplier_candidates = Array(multiplier_candidates).map(&:to_f)
      @performance_scores = Hash.new(0.0)
      # Initialize with size from candles or 0 if not available yet
      candles_size = series.respond_to?(:candles) ? (series.candles&.size || 0) : 0
      @adaptive_multipliers = Array.new(candles_size, @base_multiplier)
      @atr_values = []
    end

    def call
      # Handle both CandleSeries objects and objects with candles array
      if series.respond_to?(:highs) && series.respond_to?(:lows) && series.respond_to?(:closes)
        highs = series.highs
        lows = series.lows
        closes = series.closes
      elsif series.respond_to?(:candles)
        # Extract from candles array
        candles = series.candles
        return default_result if candles.blank?

        # CRITICAL: Ensure candles are sorted by timestamp before extracting values
        # Indicators assume chronological order - unsorted candles will produce incorrect calculations
        if series.respond_to?(:ensure_sorted!)
          series.ensure_sorted!
        elsif candles.first.respond_to?(:timestamp)
          # Fallback: sort candles array directly if ensure_sorted! not available
          candles.sort_by!(&:timestamp)
        end

        highs = candles.map(&:high)
        lows = candles.map(&:low)
        closes = candles.map(&:close)
      else
        return default_result
      end

      return default_result if highs.nil? || lows.nil? || closes.nil?
      return default_result if highs.empty? || lows.empty? || closes.empty?

      minimum_required = [training_period, period + 1].max
      return default_result if closes.size < minimum_required

      @atr_values = calculate_adaptive_atr(highs, lows, closes)
      optimize_multipliers_with_clustering(closes, atr_values)
      supertrend_line = calculate_adaptive_supertrend(highs, lows, closes, atr_values, adaptive_multipliers)

      last_index = last_valid_index(supertrend_line)
      trend = determine_trend(supertrend_line, closes, last_index)

      {
        line: supertrend_line,
        values: supertrend_line.compact,
        trend: trend,
        last_value: last_index ? supertrend_line[last_index] : nil,
        atr: atr_values,
        adaptive_multipliers: adaptive_multipliers
      }
    end

    # Expose the latest volatility regime for external diagnostics.
    def get_current_volatility_regime(index)
      return :unknown if index.nil? || index < training_period

      multiplier = adaptive_multipliers[index] || base_multiplier

      case multiplier
      when 0...base_multiplier
        :low
      when base_multiplier...(base_multiplier + 0.75)
        :medium
      else
        :high
      end
    end

    def get_performance_metrics
      {
        multiplier_scores: performance_scores.dup,
        total_clusters: num_clusters,
        training_period: training_period
      }
    end

    def get_adaptive_multiplier(index)
      adaptive_multipliers[index] || base_multiplier
    end

    private

    def default_result
      {
        line: [],
        values: [],
        trend: nil,
        last_value: nil,
        atr: [],
        adaptive_multipliers: []
      }
    end

    def calculate_adaptive_atr(highs, lows, closes)
      size = closes.size
      true_ranges = Array.new(size)

      size.times do |i|
        high = highs[i]
        low = lows[i]
        next if high.nil? || low.nil?

        if i.zero?
          true_ranges[i] = high - low
          next
        end

        prev_close = closes[i - 1]
        next if prev_close.nil?

        candidates = [
          high - low,
          (high - prev_close).abs,
          (low - prev_close).abs
        ].compact

        true_ranges[i] = candidates.max
      end

      atr = Array.new(size)

      size.times do |i|
        next if true_ranges[i].nil?

        if i == period
          window_start = [1, i - period + 1].max
          window = true_ranges[window_start..i].compact
          atr[i] = window.any? ? window.sum / window.size.to_f : nil
          next
        end

        next unless i > period

        prev_atr = atr[i - 1]
        range = true_ranges[i]
        next if prev_atr.nil? || range.nil?

        volatility_factor = calculate_volatility_factor(closes, i)
        adaptive_alpha = [0.05, 0.2 / (1.0 + volatility_factor)].max
        atr[i] = (adaptive_alpha * range) + ((1.0 - adaptive_alpha) * prev_atr)
      end

      atr
    end

    def calculate_volatility_factor(closes, index)
      return 1.0 if index < 20 || index >= closes.size

      recent_window = closes[(index - 19)..index]
      historical_window = closes[[index - 100, 0].max..index]

      recent_returns = returns_for_window(recent_window)
      historical_returns = returns_for_window(historical_window)

      recent_vol = volatility_from_returns(recent_returns)
      historical_vol = volatility_from_returns(historical_returns)

      return 1.0 if historical_vol.zero?

      recent_vol / (historical_vol + 1e-8)
    end

    def returns_for_window(window)
      return [] if window.nil? || window.size < 2

      window.each_cons(2).filter_map do |a, b|
        next if a.to_f.zero?

        (b - a) / a.to_f
      end
    end

    def volatility_from_returns(returns)
      return 0.0 if returns.empty?

      sum_sq = returns.sum { |r| r * r }
      Math.sqrt(sum_sq / returns.size.to_f)
    end

    def optimize_multipliers_with_clustering(closes, atr)
      size = closes.size
      return adaptive_multipliers if size <= training_period

      (training_period...size).each do |i|
        features = extract_volatility_features(closes, atr, i)
        next if features.empty?

        cluster_assignment = perform_kmeans_clustering(features)
        optimal_multiplier = select_optimal_multiplier(cluster_assignment)

        adaptive_multipliers[i] = optimal_multiplier
        update_performance_scores(i, closes, atr, optimal_multiplier)
      end

      backfill_adaptive_multipliers
    end

    def extract_volatility_features(closes, atr, current_index)
      return [] if current_index < period + 10

      lookback_start = [current_index - training_period, period].max
      features = []

      (lookback_start...current_index).each do |i|
        next if atr[i].nil?

        atr_window = atr[lookback_start...current_index].compact
        avg_atr = atr_window.any? ? atr_window.sum / atr_window.size.to_f : atr[i]
        normalized_atr = avg_atr&.zero? ? 1.0 : atr[i] / (avg_atr + 1e-8)

        volatility = if i >= 10
                       recent_prices = closes[(i - 9)..i]
                       returns = returns_for_window(recent_prices)
                       volatility_from_returns(returns)
                     else
                       0.0
                     end

        ma_period = [10, i + 1].min
        ma_start = [i - ma_period + 1, 0].max
        ma_prices = closes[ma_start..i] || []
        moving_avg = ma_prices.any? ? ma_prices.sum / ma_prices.size.to_f : closes[i].to_f
        trend_strength = moving_avg.zero? ? 0.0 : (closes[i] - moving_avg) / moving_avg

        features << [normalized_atr.to_f, volatility * 100.0, trend_strength * 100.0]
      end

      features
    end

    def perform_kmeans_clustering(features)
      k = [num_clusters, features.size].min
      return 0 if k <= 1

      centroids = features.sample(k)
      assignments = []

      MAX_KMEANS_ITERATIONS.times do
        assignments = features.map do |point|
          distances = centroids.map { |centroid| euclidean_distance(point, centroid) }
          distances.index(distances.min) || 0
        end

        new_centroids = []
        k.times do |cluster|
          cluster_points = features.each_with_index.filter_map { |point, idx| point if assignments[idx] == cluster }
          if cluster_points.empty?
            new_centroids << centroids[cluster]
          else
            dims = cluster_points.first.size
            mean = Array.new(dims) do |dim|
              cluster_points.sum { |point| point[dim] } / cluster_points.size.to_f
            end
            new_centroids << mean
          end
        end

        break if converged?(centroids, new_centroids)

        centroids = new_centroids
      end

      assignments.last || 0
    end

    def converged?(centroids, new_centroids)
      centroids.zip(new_centroids).all? do |old_centroid, new_centroid|
        euclidean_distance(old_centroid, new_centroid) < 0.001
      end
    end

    def euclidean_distance(point1, point2)
      return Float::INFINITY if point1.nil? || point2.nil?

      sum = 0.0
      point1.each_index do |idx|
        sum += (point1[idx] - point2[idx])**2
      end
      Math.sqrt(sum)
    end

    def select_optimal_multiplier(cluster_assignment)
      candidates = case cluster_assignment
                   when 0
                     multiplier_candidates.select { |mult| mult <= base_multiplier + 0.5 }
                   when 1
                     multiplier_candidates.select { |mult| mult.between?(base_multiplier, base_multiplier + 1.0) }
                   when 2
                     multiplier_candidates.select { |mult| mult >= base_multiplier + 0.5 }
                   else
                     []
                   end

      candidates = multiplier_candidates if candidates.empty?
      candidates.max_by { |mult| performance_scores[mult] }
    end

    def update_performance_scores(current_index, closes, atr, used_multiplier)
      return if current_index < period + 5
      return if current_index + 1 >= closes.size

      highs = series.highs
      lows = series.lows

      lookback = 5
      start_idx = [current_index - lookback, period].max
      correct_signals = 0
      total_signals = 0

      (start_idx...current_index).each do |i|
        next if atr[i].nil?

        mid = average_price(highs[i], lows[i])
        next if mid.nil?

        upper_band = mid + (used_multiplier * atr[i])
        lower_band = mid - (used_multiplier * atr[i])

        current_close = closes[i]
        next_close = closes[i + 1]
        next if current_close.nil? || next_close.nil?

        if current_close > upper_band && next_close > current_close
          correct_signals += 1
        elsif current_close < lower_band && next_close < current_close
          correct_signals += 1
        end

        total_signals += 1
      end

      return if total_signals.zero?

      accuracy = correct_signals.to_f / total_signals
      performance_scores[used_multiplier] =
        ((1 - performance_alpha) * performance_scores[used_multiplier]) +
        (performance_alpha * accuracy)
    end

    def calculate_adaptive_supertrend(highs, lows, closes, atr, multipliers)
      size = closes.size
      upperband = Array.new(size)
      lowerband = Array.new(size)
      supertrend = Array.new(size)

      size.times do |i|
        next if atr[i].nil? || multipliers[i].nil?

        mid = average_price(highs[i], lows[i])
        next if mid.nil?

        multiplier = multipliers[i]
        upperband[i] = mid + (multiplier * atr[i])
        lowerband[i] = mid - (multiplier * atr[i])
      end

      size.times do |i|
        next if atr[i].nil? || upperband[i].nil? || lowerband[i].nil?

        if i <= period
          supertrend[i] = closes[i] && closes[i] <= upperband[i] ? upperband[i] : lowerband[i]
          next
        end

        prev_supertrend = supertrend[i - 1]
        prev_upper = upperband[i - 1]
        prev_lower = lowerband[i - 1]

        if prev_supertrend.nil? || prev_upper.nil? || prev_lower.nil?
          supertrend[i] = closes[i] && closes[i] <= upperband[i] ? upperband[i] : lowerband[i]
          next
        end

        supertrend[i] = if prev_supertrend == prev_upper
                          if closes[i] && closes[i] <= upperband[i]
                            [upperband[i], prev_supertrend].compact.min
                          else
                            lowerband[i]
                          end
                        elsif closes[i] && closes[i] >= lowerband[i]
                          [lowerband[i], prev_supertrend].compact.max
                        else
                          upperband[i]
                        end
      end

      supertrend
    end

    def determine_trend(supertrend, closes, last_index)
      return nil if last_index.nil?

      last_close = closes[last_index]
      last_line = supertrend[last_index]
      return nil if last_close.nil? || last_line.nil?

      last_close >= last_line ? :bullish : :bearish
    end

    def last_valid_index(values)
      (values.size - 1).downto(0) do |i|
        return i unless values[i].nil?
      end
      nil
    end

    def average_price(high, low)
      return nil if high.nil? || low.nil?

      (high + low) / 2.0
    end

    def backfill_adaptive_multipliers
      last_value = base_multiplier
      adaptive_multipliers.each_index do |i|
        if adaptive_multipliers[i].nil?
          adaptive_multipliers[i] = last_value
        else
          last_value = adaptive_multipliers[i]
        end
      end
      adaptive_multipliers
    end
  end
end
