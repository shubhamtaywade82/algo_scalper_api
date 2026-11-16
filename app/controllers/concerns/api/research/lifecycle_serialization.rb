# frozen_string_literal: true

module Api
  module Research
    module LifecycleSerialization
      extend ActiveSupport::Concern

      private

      def serialize_lifecycle(lifecycle)
        {
          id: lifecycle.id,
          underlying_symbol: lifecycle.underlying_symbol,
          expiry_flag: lifecycle.expiry_flag,
          option_type: lifecycle.option_type,
          strike_label: lifecycle.strike_label,
          actual_strike: lifecycle.actual_strike&.to_f,
          interval: lifecycle.interval,
          status: lifecycle.status,
          entry_ts: lifecycle.entry_ts&.iso8601,
          entry_premium: lifecycle.entry_premium&.to_f,
          peak_ts: lifecycle.peak_ts&.iso8601,
          peak_premium: lifecycle.peak_premium&.to_f,
          peak_return_pct: lifecycle.peak_return_pct&.to_f,
          minutes_to_peak: lifecycle.minutes_to_peak,
          peak_duration_minutes: lifecycle.peak_duration_minutes,
          decay_start_ts: lifecycle.decay_start_ts&.iso8601,
          end_ts: lifecycle.end_ts&.iso8601,
          end_premium: lifecycle.end_premium&.to_f,
          end_return_pct: lifecycle.end_return_pct&.to_f,
          max_drawdown_after_peak_pct: lifecycle.max_drawdown_after_peak_pct&.to_f,
          threshold_minutes: lifecycle.threshold_minutes,
          underlying_context: lifecycle.underlying_context
        }
      end
    end
  end
end
