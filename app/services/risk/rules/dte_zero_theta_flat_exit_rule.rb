# frozen_string_literal: true

module Risk
  module Rules
    # Force-exits 0-DTE long options after the afternoon theta cliff when the trade
    # is not holding a meaningful profit. Complements DteEntryWindowGuard (no new entries).
    class DteZeroThetaFlatExitRule < BaseRule
      PRIORITY = 29

      DEFAULT_AFTER_TIME = '12:30'
      DEFAULT_MIN_PNL_PCT_TO_HOLD = 0.03

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?
        return no_action_result unless zero_dte_position?(context.tracker)
        return no_action_result unless past_after_time?

        pnl_pct = context.pnl_pct.to_f
        return no_action_result if pnl_pct >= min_pnl_pct_to_hold

        exit_result(
          reason: zero_dte_exit_reason(pnl_pct: pnl_pct),
          metadata: {
            path: 'dte_zero_theta_flat',
            dte_at_entry: 0,
            after_time: after_time_hhmm,
            min_pnl_pct_to_hold: min_pnl_pct_to_hold,
            pnl_pct: pnl_pct
          }
        )
      rescue StandardError => e
        Rails.logger.error("[DteZeroThetaFlatExitRule] #{e.class} - #{e.message}")
        skip_result
      end

      def enabled?(_context = nil)
        rule_config.fetch(:enabled, true) != false
      end

      private

      def rule_config
        AlgoConfig.fetch.dig(:risk, :dte_zero_exit) || {}
      rescue StandardError
        {}
      end

      def zero_dte_exit_reason(pnl_pct:)
        "DTE_ZERO_THETA_FLAT (0-DTE after #{after_time_hhmm} IST, " \
          "pnl #{(pnl_pct * 100).round(2)}% < hold #{(min_pnl_pct_to_hold * 100).round(1)}%)"
      end

      def zero_dte_position?(tracker)
        dte = dte_at_entry(tracker)
        !dte.nil? && dte.zero?
      end

      def dte_at_entry(tracker)
        meta = tracker&.meta || {}
        val = meta['dte_at_entry'] || meta[:dte_at_entry]
        return val.to_i if val.present?

        expiry = meta['expiry_date'] || meta[:expiry_date]
        return nil if expiry.blank?

        (Date.parse(expiry.to_s) - Time.zone.today).to_i
      rescue ArgumentError
        nil
      end

      def past_after_time?
        now_hhmm = Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
        now_hhmm >= after_time_hhmm
      end

      def after_time_hhmm
        rule_config[:after_time].presence ||
          Trading::DteParameterResolver.max_entry_time(dte: 0) ||
          DEFAULT_AFTER_TIME
      end

      def min_pnl_pct_to_hold
        rule_config.fetch(:min_pnl_pct_to_hold, DEFAULT_MIN_PNL_PCT_TO_HOLD).to_f
      end
    end
  end
end
