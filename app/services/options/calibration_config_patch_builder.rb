# frozen_string_literal: true

module Options
  # Derives algo.yml-compatible config overrides from weighted calibration stats.
  #
  # Input stats are in percentage POINTS (e.g. avg_gain: 14.2 means 14.2%).
  # Formulas divide by 100 to produce decimal config values (e.g. 0.064).
  #
  # Only emits keys where the proposed value differs from the current active
  # config by ≥10%, to avoid noisy patches that change nothing meaningful.
  #
  # Returns a string-keyed Hash safe for deep_merge into +algo_config_document+.
  # adaptive_drawdown is deliberately excluded — it is an array-of-hashes
  # that cannot be safely deep-merged with plain Hash#deep_merge.
  class CalibrationConfigPatchBuilder
    CHANGE_THRESHOLD = 0.10 # 10% minimum change to include a key

    def self.build(combined_stats:, symbol:)
      new(combined_stats: combined_stats, symbol: symbol).build
    end

    def initialize(combined_stats:, symbol:)
      # deep_symbolize_keys ensures consistent access regardless of whether the
      # caller passed a symbol-keyed hash (from StrikeAggregator) or a
      # string-keyed hash (e.g. CalibrationRun#raw_stats loaded from JSONB).
      @stats  = combined_stats.deep_symbolize_keys
      @symbol = symbol.to_s.downcase
    end

    def build
      current = AlgoConfig.fetch
      proposed = derive_values
      filter_significant_changes(proposed, current).deep_stringify_keys
    end

    private

    def derive_values
      avg_gain        = @stats[:avg_gain].to_f
      avg_retrace_abs = @stats[:avg_retrace_abs].to_f

      sessions       = @stats[:sessions] || {}
      weak_midday    = sessions[:midday_oc].to_f < 0.0
      weak_afternoon = sessions[:afternoon_oc].to_f < 0.0

      target_pct     = clamp(avg_gain * 0.45 / 100.0, 0.08, 0.35)
      activation_pct = clamp(avg_gain * 0.25 / 100.0, 0.020, 0.08)
      drawdown_pct   = clamp(avg_retrace_abs * 0.80 / 100.0, 0.015, 0.060)
      distance       = clamp(drawdown_pct * 1.1, 0.030, 0.12)
      lock_pct       = clamp(avg_gain * 0.20 / 100.0, 0.06, 0.15)
      trail_pct      = clamp(1.0 - (avg_retrace_abs * 0.80 / 100.0), 0.55, 0.92)
      early_trigger  = clamp(activation_pct * 0.85, 0.020, 0.06)
      breakeven      = clamp(activation_pct * 1.5, 0.040, 0.12)
      activation_it  = clamp(target_pct * 0.55, 0.08, 0.20)
      time_stop_mins = suggested_time_stop(weak_midday: weak_midday, weak_afternoon: weak_afternoon)

      {
        risk: {
          percentage_pnl_exit: { target_pct: target_pct },
          trailing: { activation_pct: activation_pct, drawdown_pct: drawdown_pct },
          profit_floor: { lock_pct: lock_pct, trail_pct: trail_pct },
          time_stop: { trend: { @symbol.upcase.to_sym => time_stop_mins } },
          institutional_trailing: {
            @symbol.to_sym => {
              trailing_distance: distance,
              early_trigger: early_trigger,
              breakeven_trigger: breakeven,
              activation_trigger: activation_it
            }
          }
        }
      }
    end

    def suggested_time_stop(weak_midday:, weak_afternoon:)
      base = case @symbol.upcase
             when 'NIFTY'   then 20
             when 'SENSEX'  then 10
             else 15
             end
      base = (base * 0.8).round if weak_midday
      base = (base * 0.9).round if weak_afternoon
      [base, 6].max
    end

    # Recursively walks proposed and current; returns only paths where
    # proposed leaf differs from current leaf by ≥ CHANGE_THRESHOLD (10%).
    def filter_significant_changes(proposed, current, path = [])
      result = {}
      proposed.each do |key, value|
        current_value = current.is_a?(Hash) ? (current[key] || current[key.to_s]) : nil

        if value.is_a?(Hash)
          sub = filter_significant_changes(value, current_value || {}, path + [key])
          result[key] = sub unless sub.empty?
        elsif significant_change?(value, current_value)
          result[key] = value
        end
      end
      result
    end

    def significant_change?(proposed_val, current_val)
      return true if current_val.nil? || current_val.to_f.zero?

      deviation = (proposed_val.to_f - current_val.to_f).abs / current_val.to_f
      deviation >= CHANGE_THRESHOLD
    end

    def clamp(value, min, max)
      [[value, min].max, max].min.round(4)
    end
  end
end
