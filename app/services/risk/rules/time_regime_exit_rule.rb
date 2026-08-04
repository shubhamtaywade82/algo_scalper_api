# frozen_string_literal: true

module Risk
  module Rules
    # Time Regime Exit Rule - session-aware profit booking & stop tightening for options buying
    #
    # PURPOSE: Theta burn and IV crush risk are not constant through the day. The bot already
    # classifies each moment into a session regime (Live::TimeRegimeService — S1 Open Expansion,
    # S2 Trend Continuation, S3 Chop/Theta zone, S4 Close/Gamma zone) with per-regime
    # tp_multiplier / sl_multiplier / max_tp_rupees, but until now nothing outside the entry
    # guard consumed those multipliers — exits ran on flat sl_pct/tp_pct regardless of session.
    #
    # This rule scales the base SL/TP thresholds by the active regime's multipliers so that:
    # - In the Chop/Theta zone (S3) and Close/Gamma zone (S4), profits are booked faster
    #   (smaller TP) and losses are cut sooner (tighter SL) — exactly where theta burn and
    #   IV crush are most dangerous for an option buyer.
    # - In the Trend Continuation zone (S2, multiplier 1.0), this rule is a no-op and the
    #   standard StopLoss/TakeProfit/PercentagePnl rules own the decision — baseline
    #   behavior in the best trading window is unchanged.
    # - A regime's max_tp_rupees cap (e.g. ₹1,500 in chop, ₹2,000 near close) provides an
    #   absolute rupee ceiling on top of the percentage-based target.
    #
    # Priority: 22 (between StopLossRule=20 and PercentagePnlRule=25) so the session-aware
    # thresholds get first say whenever the regime tightens the baseline; it's a no-op
    # (skip) whenever the regime doesn't adjust thresholds, deferring to the generic rules.
    class TimeRegimeExitRule < BaseRule
      PRIORITY = 22

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        regime_service = Live::TimeRegimeService.instance
        regime = regime_service.current_regime
        tp_multiplier = regime_service.tp_multiplier(regime)
        sl_multiplier = regime_service.sl_multiplier(regime)

        # No-op when the regime doesn't tighten anything — let the generic rules own it.
        return skip_result if tp_multiplier == 1.0 && sl_multiplier == 1.0

        pnl_pct = context.pnl_pct.to_f
        pnl_rupees = context.pnl_rupees.to_f

        base_tp_pct = base_take_profit_pct
        base_sl_pct = base_stop_loss_pct

        adjusted_tp_pct = base_tp_pct * tp_multiplier
        adjusted_sl_pct = base_sl_pct * sl_multiplier
        max_tp_rupees = regime_service.max_tp_rupees(regime)

        if take_profit_hit?(pnl_pct: pnl_pct, pnl_rupees: pnl_rupees, adjusted_tp_pct: adjusted_tp_pct,
                            max_tp_rupees: max_tp_rupees)
          return exit_result(
            reason: "TIME_REGIME_TAKE_PROFIT (#{regime} tp_mult=#{tp_multiplier})",
            metadata: {
              path: 'time_regime_take_profit',
              regime: regime.to_s,
              pnl_pct: (pnl_pct * 100.0).round(2),
              pnl_rupees: pnl_rupees.round(2),
              base_tp_pct: base_tp_pct,
              tp_multiplier: tp_multiplier,
              adjusted_tp_pct: adjusted_tp_pct.round(4),
              max_tp_rupees: max_tp_rupees
            }
          )
        end

        if pnl_pct <= -adjusted_sl_pct
          return exit_result(
            reason: "TIME_REGIME_STOP_LOSS (#{regime} sl_mult=#{sl_multiplier})",
            metadata: {
              path: 'time_regime_stop_loss',
              regime: regime.to_s,
              pnl_pct: (pnl_pct * 100.0).round(2),
              base_sl_pct: base_sl_pct,
              sl_multiplier: sl_multiplier,
              adjusted_sl_pct: adjusted_sl_pct.round(4)
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[TimeRegimeExitRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      private

      def take_profit_hit?(pnl_pct:, pnl_rupees:, adjusted_tp_pct:, max_tp_rupees:)
        return true if adjusted_tp_pct.positive? && pnl_pct >= adjusted_tp_pct
        return true if max_tp_rupees.present? && max_tp_rupees.to_f.positive? && pnl_rupees >= max_tp_rupees.to_f

        false
      end

      def base_take_profit_pct
        risk_cfg = AlgoConfig.fetch[:risk] || {}
        (config_take_profit || risk_cfg[:tp_pct] || 0.25).to_f
      end

      def base_stop_loss_pct
        risk_cfg = AlgoConfig.fetch[:risk] || {}
        (risk_cfg[:sl_pct] || risk_cfg.dig(:stop_loss, :value) || 0.10).to_f
      end

      def config_take_profit
        config[:take_profit]
      end
    end
  end
end
