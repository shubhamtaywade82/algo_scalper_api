# frozen_string_literal: true

module Orders
  # Executes order modifications and placement on the broker via BracketPlacer
  class Executor
    class << self
      def place_buy(symbol:, qty:, segment:, security_id:, ltp: nil)
        Orders.config.gateway.place_market(
          side: 'buy',
          segment: segment,
          security_id: security_id,
          qty: qty,
          meta: {
            symbol: symbol,
            ltp: ltp
          }
        )
      end

      def update_sl(tracker:, sl_price:, reason:)
        return false unless tracker&.active? && sl_price&.positive?

        # Use BracketPlacer to update the SL
        # BracketPlacer handles both ActiveCache updates and future broker modifications
        result = Orders::BracketPlacer.update_bracket(
          tracker: tracker,
          sl_price: sl_price.round(2),
          reason: reason
        )

        result[:success] == true
      rescue StandardError => e
        Rails.logger.error("[Orders::Executor] Failed to update SL for #{tracker&.order_no}: #{e.message}")
        false
      end

      def exit_market!(tracker:, reason: 'manual_exit')
        return false unless tracker&.active?

        Rails.logger.info("[Orders::Executor] EXIT_MARKET triggered for #{tracker.symbol} (ID: #{tracker.id}). Reason: #{reason}")

        # Call the gateway to exit the position
        Orders.config.gateway.exit_market(tracker: tracker)
      rescue StandardError => e
        Rails.logger.error("[Orders::Executor] Failed to exit market for #{tracker&.order_no}: #{e.message}")
        false
      end
    end
  end
end
