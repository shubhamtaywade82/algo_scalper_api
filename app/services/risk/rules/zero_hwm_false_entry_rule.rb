# frozen_string_literal: true

module Risk
  module Rules
    # Detects false entries: positions that never moved into profit (HWM ≈ 0) after a
    # configurable hold threshold, then exits immediately to prevent slow bleed.
    #
    # A "false entry" is one where the market moved against us from the very first tick —
    # wrong direction, stale signal, or bad fill. Holding these for the full TIME_STOP
    # window is expensive (e.g., ID=21: -₹6,150 over 40 minutes with HWM=₹0 throughout).
    #
    # Config path (algo.yml):
    #   risk:
    #     zero_hwm_false_entry:
    #       enabled: true
    #       min_hold_seconds: 120   # grace period before the rule can fire
    #       hwm_threshold_rupees: 0 # exit if HWM is at or below this after grace period
    class ZeroHwmFalseEntryRule < BaseRule
      PRIORITY = 15 # Fires before TimeStopRule (40) — fast-exits confirmed false entries

      DEFAULT_MIN_HOLD_SECONDS   = 120
      DEFAULT_HWM_THRESHOLD      = 0.0

      def evaluate(context)
        return skip_result unless context.active?
        return no_action_result unless enabled?(context)

        tracker = context.tracker
        elapsed  = (Time.current - tracker.created_at).to_f
        return no_action_result if elapsed < min_hold_seconds(context)

        hwm_rupees = context.position.hwm_pnl.to_f
        return no_action_result if hwm_rupees > hwm_threshold(context)

        exit_result(
          reason: "ZERO_HWM_FALSE_ENTRY",
          metadata: {
            path:               "zero_hwm_false_entry",
            elapsed_seconds:    elapsed.round(1),
            min_hold_seconds:   min_hold_seconds(context),
            hwm_rupees:         hwm_rupees,
            hwm_threshold:      hwm_threshold(context),
            current_ltp:        context.current_ltp.to_f,
            entry_price:        tracker.entry_price.to_f
          }
        )
      end

      def enabled?(context = nil)
        cfg = rule_config(context)
        cfg.fetch(:enabled, true) != false
      end

      private

      def rule_config(context)
        return {} unless context

        (context.risk_config.dig(:risk, :zero_hwm_false_entry) ||
         context.risk_config[:zero_hwm_false_entry] || {}).deep_symbolize_keys
      end

      def min_hold_seconds(context)
        rule_config(context).fetch(:min_hold_seconds, DEFAULT_MIN_HOLD_SECONDS).to_f
      end

      def hwm_threshold(context)
        rule_config(context).fetch(:hwm_threshold_rupees, DEFAULT_HWM_THRESHOLD).to_f
      end
    end
  end
end
