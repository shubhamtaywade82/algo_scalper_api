# frozen_string_literal: true

module Orders
  class Manager
    class << self
      def place_market_buy(segment:, security_id:, qty:, reason:, metadata: {})
        return unless segment.present? && security_id.present?

        client_order_id = build_client_order_id(segment, security_id, reason)
        Rails.logger.info(
          "[Orders::Manager] BUY #{segment}-#{security_id} qty=#{qty} reason=#{reason} metadata=#{metadata.inspect}"
        )

        Orders::Placer.buy_market!(
          seg: segment,
          sid: security_id,
          qty: qty,
          client_order_id: client_order_id
        )
      end

      private

      def build_client_order_id(segment, security_id, reason)
        normalized_reason = reason.to_s.parameterize.presence || 'signal'
        timestamp = Time.current.strftime('%H%M%S')
        "#{segment}-#{security_id}-#{normalized_reason}-#{timestamp}"
      end
    end
  end
end
