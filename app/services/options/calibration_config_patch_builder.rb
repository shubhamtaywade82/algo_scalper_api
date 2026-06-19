# frozen_string_literal: true

module Options
  # Derives algo config patch overrides from weighted calibration stats or trailing params.
  class CalibrationConfigPatchBuilder
    CHANGE_THRESHOLD = 0.10

    def self.build(combined_stats:, symbol:)
      new(combined_stats: combined_stats, symbol: symbol).build
    end

    def self.from_trailing_params(symbol:, params:)
      index_key = symbol.to_s.downcase
      patch = {
        risk: {
          institutional_trailing: {
            index_key => params.transform_keys(&:to_s)
          }
        }
      }
      new(combined_stats: {}, symbol: symbol, raw_patch: patch).build
    end

    def initialize(combined_stats:, symbol:, raw_patch: nil)
      @stats = combined_stats || {}
      @symbol = symbol.to_s.downcase
      @raw_patch = raw_patch
    end

    def build
      current = AlgoConfig.fetch
      proposed = @raw_patch || derive_values
      filter_significant_changes(proposed, current).deep_stringify_keys
    end

    private

    def derive_values
      avg_gain = @stats[:avg_gain].to_f
      avg_retrace_abs = @stats[:avg_retrace_abs].to_f

      target_pct = clamp(avg_gain * 0.45 / 100.0, 0.08, 0.35)
      activation_pct = clamp(avg_gain * 0.25 / 100.0, 0.020, 0.08)
      drawdown_pct = clamp(avg_retrace_abs * 0.80 / 100.0, 0.015, 0.060)
      distance = clamp(drawdown_pct * 1.1, 0.030, 0.12)
      lock_pct = clamp(avg_gain * 0.20 / 100.0, 0.06, 0.15)
      trail_pct = clamp(1.0 - (avg_retrace_abs * 0.80 / 100.0), 0.55, 0.92)
      early_trigger = clamp(activation_pct * 0.85, 0.020, 0.06)
      breakeven = clamp(activation_pct * 1.5, 0.040, 0.12)
      activation_it = clamp(target_pct * 0.55, 0.08, 0.20)

      {
        risk: {
          percentage_pnl_exit: { target_pct: target_pct },
          trailing: { activation_pct: activation_pct, drawdown_pct: drawdown_pct },
          profit_floor: { lock_pct: lock_pct, trail_pct: trail_pct },
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

    def filter_significant_changes(proposed, current, path = [])
      result = {}
      proposed.each do |key, value|
        current_value = current.is_a?(Hash) ? (current[key] || current[key.to_s]) : nil

        if value.is_a?(Hash)
          sub = filter_significant_changes(value, current_value || {}, path + [key])
          result[key] = sub unless sub.empty?
        elsif significant_change?(value, current_value)
          result[key] = value.is_a?(Numeric) ? value.round(4) : value
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
