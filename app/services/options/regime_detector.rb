# frozen_string_literal: true

module Options
  class RegimeDetector
    SIGMA_THRESHOLD = 1.5
    MIN_HISTORY_RUNS = 12
    CHECKED_METRICS = %w[avg_retrace_abs avg_loss_abs oc_stddev].freeze

    def self.check(symbol:, combined_stats:)
      new(symbol: symbol, combined_stats: combined_stats).check
    end

    def initialize(symbol:, combined_stats:)
      @symbol = symbol.to_s.upcase
      @combined_stats = combined_stats
    end

    def check
      history = CalibrationRun.where(symbol: @symbol).order(created_at: :desc).to_a
      if history.size < MIN_HISTORY_RUNS
        return {
          shift: false,
          reason: "insufficient_history (fewer than #{MIN_HISTORY_RUNS} runs)"
        }
      end

      CHECKED_METRICS.each do |metric|
        historical_vals = history.map { |run| run.raw_stats[metric].to_f }
        mean = historical_vals.sum / historical_vals.size
        sigma = stddev(historical_vals)
        next if sigma.zero?

        current_val = @combined_stats[metric.to_sym].to_f
        deviation_sigma = (current_val - mean).abs / sigma
        next unless deviation_sigma > SIGMA_THRESHOLD

        direction = current_val > mean ? 'higher' : 'lower'
        return {
          shift: true,
          reason: "#{metric}: #{current_val.round(2)}% is #{deviation_sigma.round(1)}σ " \
                  "#{direction} than historical mean (#{mean.round(2)}%) — regime shift likely"
        }
      end

      { shift: false, reason: 'stable (all metrics within 1.5σ of historical mean)' }
    end

    private

    def stddev(values)
      return 0.0 if values.size < 2

      mean = values.sum.to_f / values.size
      variance = values.sum { |value| (value - mean)**2 } / values.size
      Math.sqrt(variance)
    end
  end
end
