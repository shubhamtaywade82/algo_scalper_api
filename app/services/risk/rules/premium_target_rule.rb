# frozen_string_literal: true

module Risk
  module Rules
    # SELLING's take-profit: exit once enough of the premium received has decayed
    # away. Selling's equivalent of TakeProfitRule for buying.
    class PremiumTargetRule < BaseRule
      PRIORITY = 10

      DEFAULT_PREMIUM_TARGET_PCT = 50.0

      def evaluate(context)
        return no_action_result unless enabled?
        return no_action_result unless context.active?
        return no_action_result unless context.tracker.short_position?

        # premium_received is a TOTAL (price x qty) but current_ltp is per-unit — both
        # sides of the comparison must be per-unit.
        quantity = context.tracker.quantity.to_i
        return no_action_result unless quantity.positive?

        premium_received_per_unit = context.tracker.premium_received.to_f / quantity
        return no_action_result unless premium_received_per_unit.positive?

        current_ltp = context.current_ltp.to_f
        return no_action_result unless current_ltp.positive?

        decay_captured = premium_received_per_unit - current_ltp
        decay_pct = (decay_captured / premium_received_per_unit) * 100
        target_pct = target_pct(context)

        return no_action_result unless decay_pct >= target_pct

        reason = "PREMIUM_TARGET (#{decay_pct.round(1)}% decay of #{premium_received_per_unit.round(2)} received, target #{target_pct}%)"
        exit_result(reason: reason, metadata: { decay_pct: decay_pct, premium_received: premium_received_per_unit, current_premium: current_ltp })
      end

      private

      def target_pct(context)
        context.config_value(:premium_target_pct, DEFAULT_PREMIUM_TARGET_PCT).to_f
      end
    end
  end
end
