# frozen_string_literal: true

module Options
  # Detects regime shifts by comparing current calibration stats against
  # ALL prior CalibrationRun records for the symbol using sigma thresholds.
  #
  # A shift is flagged when ANY of the three checked metrics exceeds
  # SIGMA_THRESHOLD standard deviations from the historical mean.
  # Checked metrics: avg_retrace_abs, avg_loss_abs, oc_stddev
  #
  # Requires at least 12 historical runs before detection is active.
  # Returns: { shift: bool, reason: String }
  #
  # NOTE: The +combined_stats+ parameter must be a Hash with symbol keys
  # (as returned by StrikeAggregator.combine), not string keys.
  class RegimeDetector
    SIGMA_THRESHOLD  = 1.5
    MIN_HISTORY_RUNS = 12
    CHECKED_METRICS  = %w[avg_retrace_abs avg_loss_abs oc_stddev].freeze

    def self.check(symbol:, combined_stats:)
      new(symbol: symbol, combined_stats: combined_stats).check
    end

    def initialize(symbol:, combined_stats:)
      @symbol         = symbol.to_s.upcase
      @combined_stats = combined_stats
    end

    def check
      history = CalibrationRun.where(symbol: @symbol).to_a

      return { shift: false, reason: "insufficient_history (fewer than #{MIN_HISTORY_RUNS} runs)" } \
        if history.size < MIN_HISTORY_RUNS

      CHECKED_METRICS.each do |metric|
        historical_vals = history.map { |r| r.raw_stats[metric].to_f }
        mean  = historical_vals.sum / historical_vals.size
        sigma = stddev(historical_vals)

        current_val = @combined_stats[metric.to_sym].to_f

        # Edge case: sigma = 0 (constant baseline) but current differs from mean
        # This indicates a definite regime shift (any deviation from constant = infinite sigma)
        if sigma.zero? && (current_val - mean).abs > 1e-10
          direction = current_val > mean ? 'higher' : 'lower'
          reason = "#{metric}: #{current_val.round(2)} is clearly #{direction} than constant " \
                   "historical baseline (#{mean.round(2)}) — regime shift likely"
          return { shift: true, reason: reason }
        end

        deviation_sigma = (current_val - mean).abs / sigma

        next unless deviation_sigma > SIGMA_THRESHOLD
        direction = current_val > mean ? 'higher' : 'lower'
        reason = "#{metric}: #{current_val.round(2)} is #{deviation_sigma.round(1)}σ " \
                 "#{direction} than historical mean (#{mean.round(2)}) — regime shift likely"
        return { shift: true, reason: reason }
      end

      { shift: false, reason: 'stable (all metrics within 1.5σ of historical mean)' }
    end

    private

    def stddev(values)
      return 0.0 if values.size < 2

      mean     = values.sum.to_f / values.size
      variance = values.sum { |v| (v - mean)**2 } / (values.size - 1).to_f
      Math.sqrt(variance)
    end
  end
end
