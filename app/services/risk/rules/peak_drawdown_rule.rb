# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces peak drawdown exit
    # Triggers exit when current profit drops by configured percentage from peak profit
    # Includes peak-drawdown activation gating (only active after certain profit threshold)
    class PeakDrawdownRule < BaseRule
      PRIORITY = 45

      def evaluate(context)
        return skip_result unless context.active?

        # Check trailing activation threshold (pnl_pct >= trailing_activation_pct)
        # Peak drawdown rule only activates after trailing activation threshold is met
        unless context.trailing_activated?
          Rails.logger.debug(
            "[PeakDrawdownRule] Trailing not activated: pnl_pct=#{context.pnl_pct&.round(2)}% " \
            "< activation_pct=#{context.trailing_activation_pct.to_f.round(2)}%"
          )
          return skip_result
        end

        peak_profit_pct = context.peak_profit_pct
        current_profit_pct = context.pnl_pct
        return skip_result unless peak_profit_pct && current_profit_pct

        # Skip if peak is 0% or negative (position never profitable)
        # Peak drawdown rule should only trigger when position had profit and is drawing down
        if peak_profit_pct.to_f <= 0
          Rails.logger.debug(
            "[PeakDrawdownRule] Skipping: peak=#{peak_profit_pct.round(2)}% <= 0% " \
            "(position never profitable, should use Stop Loss rule instead)"
          )
          return skip_result
        end

        # Check if peak drawdown threshold is breached (uses tiered protection)
        unless peak_drawdown_triggered?(peak_profit_pct, current_profit_pct)
          return no_action_result
        end

        # Log which tier was used for transparency
        drawdown_threshold = Positions::TrailingConfig.calculate_tiered_drawdown_threshold(peak_profit_pct)
        Rails.logger.debug(
          "[PeakDrawdownRule] Tiered protection: peak=#{peak_profit_pct.round(2)}% " \
          "threshold=#{drawdown_threshold.round(2)}% drawdown=#{(peak_profit_pct - current_profit_pct).round(2)}%"
        )

        # Apply peak-drawdown activation gating (if enabled)
        if peak_drawdown_activation_enabled?
          activation_ready = peak_drawdown_active?(
            profit_pct: peak_profit_pct,
            current_sl_offset_pct: current_sl_offset_pct(context)
          )
          unless activation_ready
            Rails.logger.debug(
              "[PeakDrawdownRule] Peak drawdown gating: peak=#{peak_profit_pct.round(2)}% " \
              "sl_offset=#{current_sl_offset_pct(context)&.round(2)}% " \
              "not activated (drawdown=#{(peak_profit_pct - current_profit_pct).round(2)}%)"
            )
            return no_action_result
          end
        end

        drawdown = peak_profit_pct - current_profit_pct
        exit_result(
          reason: "peak_drawdown_exit (drawdown: #{drawdown.round(2)}%, peak: #{peak_profit_pct.round(2)}%)",
          metadata: {
            peak_profit_pct: peak_profit_pct,
            current_profit_pct: current_profit_pct,
            drawdown: drawdown,
            threshold: peak_drawdown_pct,
            trailing_activation_pct: context.trailing_activation_pct.to_f
          }
        )
      end

      private

      def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct)
        Positions::TrailingConfig.peak_drawdown_triggered?(peak_profit_pct, current_profit_pct)
      end

      def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
        Positions::TrailingConfig.peak_drawdown_active?(
          profit_pct: profit_pct,
          current_sl_offset_pct: current_sl_offset_pct
        )
      end

      def peak_drawdown_activation_enabled?
        feature_flags[:enable_peak_drawdown_activation] == true
      end

      def feature_flags
        AlgoConfig.fetch[:feature_flags] || {}
      rescue StandardError
        {}
      end

      def peak_drawdown_pct
        Positions::TrailingConfig.config[:peak_drawdown_pct] || Positions::TrailingConfig::DEFAULT_PEAK_DRAWDOWN_PCT
      end

      def current_sl_offset_pct(context)
        return context.position.sl_offset_pct if context.position.respond_to?(:sl_offset_pct) && context.position.sl_offset_pct

        entry = context.entry_price&.to_f
        sl_price = context.position.respond_to?(:sl_price) ? context.position.sl_price&.to_f : nil
        return nil unless entry&.positive? && sl_price&.positive?

        ((sl_price - entry) / entry) * 100.0
      end
    end
  end
end
