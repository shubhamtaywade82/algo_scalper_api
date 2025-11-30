# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces trailing stop based on high water mark drop (legacy method)
    # Triggers exit when PnL drops by configured percentage from high water mark
    # NOTE: This is a legacy trailing stop method. PeakDrawdownRule is preferred for new implementations.
    #
    # Trailing Activation:
    # - Only activates when pnl_pct >= trailing_activation_pct (configurable, default 10%)
    # - Based on buy value (premium × lot_size × lots), works across any capital/allocation/lot size
    # - Configurable values: 6%, 6.66%, 9.99%, 10%, 13.32%, 15%, 20%, etc.
    class TrailingStopRule < BaseRule
      PRIORITY = 50

      def evaluate(context)
        return skip_result unless context.active?

        # Check trailing activation threshold (pnl_pct >= trailing_activation_pct)
        unless context.trailing_activated?
          Rails.logger.debug(
            "[TrailingStopRule] Trailing not activated: pnl_pct=#{context.pnl_pct&.round(2)}% " \
            "< activation_pct=#{context.trailing_activation_pct.to_f.round(2)}%"
          )
          return skip_result
        end

        pnl = context.pnl_rupees
        hwm = context.high_water_mark
        return skip_result if pnl.nil? || hwm.nil? || hwm.zero?

        drop_threshold = context.config_bigdecimal(:exit_drop_pct, BigDecimal('0'))
        return skip_result if drop_threshold.zero?

        drop_pct = (hwm - pnl) / hwm
        return no_action_result unless drop_pct >= drop_threshold.to_f

        exit_result(
          reason: "TRAILING STOP drop=#{drop_pct.round(3)}",
          metadata: {
            pnl: pnl,
            hwm: hwm,
            drop_pct: drop_pct.to_f,
            drop_threshold: drop_threshold.to_f,
            trailing_activation_pct: context.trailing_activation_pct.to_f,
            pnl_pct: context.pnl_pct
          }
        )
      end
    end
  end
end
