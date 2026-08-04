# frozen_string_literal: true

module Research
  class DistributionModel
    # Builds a probability distribution summary for a list of values.
    # @param values [Array<Numeric>] List of numbers
    # @return [Hash] Detailed stats containing mean, median, std_dev, and 95% confidence intervals
    def self.build(values)
      return empty_distribution if values.blank?

      sorted = values.sort
      n = sorted.size
      mean = sorted.sum.to_f / n

      median = if n.odd?
                 sorted[n / 2]
               else
                 (sorted[(n / 2) - 1] + sorted[n / 2]) / 2.0
               end

      std_dev = 0.0
      if n > 1
        variance = sorted.sum { |x| (x - mean)**2 } / (n - 1)
        std_dev = Math.sqrt(variance)
      end

      # 95% Confidence Interval using standard error and critical t/z-score (1.96)
      standard_error = n.positive? ? std_dev / Math.sqrt(n) : 0.0
      ci_lower = mean - (1.96 * standard_error)
      ci_upper = mean + (1.96 * standard_error)

      {
        mean: mean.round(2),
        median: median.round(2),
        std_dev: std_dev.round(2),
        ci_lower: ci_lower.round(2),
        ci_upper: ci_upper.round(2),
        sample_size: n
      }
    end

    def self.empty_distribution
      {
        mean: 0.0,
        median: 0.0,
        std_dev: 0.0,
        ci_lower: 0.0,
        ci_upper: 0.0,
        sample_size: 0
      }
    end
  end
end
