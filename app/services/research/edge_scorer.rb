# frozen_string_literal: true

module Research
  class EdgeScorer
    # Calculates a probabilistic Edge Score (0 to 100) for a trade subset.
    # Formula: Expected Return * Win Rate * Reliability * Sample Size Factor * Confidence
    # @param returns [Array<Float>] Array of trade returns (as percentages, e.g. 30.0 for 30%)
    # @param success_threshold [Float] Threshold for success (e.g. 30.0%)
    # @return [Integer] Edge Score (0 to 100)
    def self.score(returns, success_threshold = 30.0)
      return 0 if returns.blank?

      sample_size = returns.size

      # 1. Expected Return (normalized, e.g. 50% = 0.5)
      mean_ret = returns.sum / sample_size
      expected_return_factor = [mean_ret / 100.0, 0.0].max

      # 2. Probability of Success (Win Rate as ratio, e.g. 70% = 0.7)
      success_count = returns.count { |r| r >= success_threshold }
      win_rate = success_count.to_f / sample_size

      # 3. Reliability (1 - Coefficient of Variation)
      reliability = 1.0
      if sample_size > 1
        variance = returns.sum { |r| (r - mean_ret)**2 } / (sample_size - 1)
        std_dev = Math.sqrt(variance)
        if mean_ret.positive?
          cv = std_dev / mean_ret
          reliability = [1.0 - cv, 0.0].max
        else
          reliability = 0.0
        end
      end

      # 4. Sample Size Factor (asymptotic scaling from 0 to 1)
      # 10 trades = ~0.46, 50 trades = ~0.78, 250 trades = ~0.95
      sample_factor = Math.log(sample_size + 1) / Math.log(300)
      sample_factor = [sample_factor, 1.0].min

      # 5. Confidence (1 - Binomial p-value of beating random chance)
      # Null hypothesis: win_rate <= 0.50 (random choice)
      p_val = HypothesisEngine.binomial_p_value(success_count, sample_size, 0.5)
      confidence = [1.0 - p_val, 0.0].max

      # Composite Edge Score
      raw_score = expected_return_factor * win_rate * reliability * sample_factor * confidence * 1000.0

      [[raw_score.round, 100].min, 0].max
    end
  end
end
