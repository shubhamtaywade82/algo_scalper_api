# frozen_string_literal: true

module Orders
  class Placer
    class << self
      def buy_market!(seg:, sid:, qty:, client_order_id:)
        return if duplicate?(client_order_id)

        order = DhanHQ::Models::Order.create(
          transaction_type: "BUY",
          exchange_segment: seg,
          security_id: sid,
          quantity: qty,
          order_type: "MARKET",
          product_type: "INTRADAY",
          validity: "DAY",
          client_order_id: client_order_id
        )
        remember(client_order_id)
        order
      end

      def sell_market!(seg:, sid:, qty:, client_order_id:)
        return if duplicate?(client_order_id)

        order = DhanHQ::Models::Order.create(
          transaction_type: "SELL",
          exchange_segment: seg,
          security_id: sid,
          quantity: qty,
          order_type: "MARKET",
          product_type: "INTRADAY",
          validity: "DAY",
          client_order_id: client_order_id
        )
        remember(client_order_id)
        order
      end

      private

      def duplicate?(client_order_id)
        Rails.cache.read("coid:#{client_order_id}").present?
      end

      def remember(client_order_id)
        Rails.cache.write("coid:#{client_order_id}", true, expires_in: 20.minutes)
      end
    end
  end
end
