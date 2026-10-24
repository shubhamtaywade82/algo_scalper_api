# frozen_string_literal: true

module Risk
  module Rules
    # SELLING's stop-loss: naked short options have unlimited risk, so this caps
    # the loss at a multiple of the premium received. Selling's equivalent of
    # StopLossRule for buying — highest priority since it's the risk cap.
    class MaxPremiumLossRule < BaseRule
      PRIORITY = 5

      DEFAULT_MAX_LOSS_MULTIPLIER = 2.0

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

        current_loss = current_ltp - premium_received_per_unit
        max_loss = premium_received_per_unit * max_loss_multiplier(context)

        return no_action_result unless current_loss > max_loss

        loss_pct = (current_loss / premium_received_per_unit) * 100
        reason = "MAX_PREMIUM_LOSS (loss #{current_loss.round(2)} = #{loss_pct.round(1)}% of #{premium_received_per_unit.round(2)} received)"
        exit_result(reason: reason, metadata: { current_loss: current_loss, max_loss: max_loss, premium_received: premium_received_per_unit })
      end

      private

      def max_loss_multiplier(context)
        context.config_value(:max_premium_loss_multiplier, DEFAULT_MAX_LOSS_MULTIPLIER).to_f
      end
    end
  end
end
