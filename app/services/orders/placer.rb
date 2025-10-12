# frozen_string_literal: true

require "digest"

module Orders
  class Placer
    class << self
      def buy_market!(seg:, sid:, qty:, client_order_id:, product_type: "INTRADAY", price: nil,
                      target_price: nil, stop_loss_price: nil, trailing_jump: nil)
        normalized_id = normalize_client_order_id(client_order_id)
        return if duplicate?(normalized_id)

        # Validate required parameters
        unless seg && sid && qty && normalized_id
          Rails.logger.error("[Orders] Missing required parameters: seg=#{seg}, sid=#{sid}, qty=#{qty}, client_order_id=#{client_order_id}")
          return nil
        end

        if normalized_id.present? && normalized_id != client_order_id
          Rails.logger.warn("[Orders] client_order_id truncated to '#{normalized_id}' (was '#{client_order_id}')")
        end

        Rails.logger.info("[Orders] Placing BUY order: seg=#{seg}, sid=#{sid}, qty=#{qty}, client_order_id=#{normalized_id}")

        payload = {
          transaction_type: "BUY",
          exchange_segment: seg,
          security_id: sid,
          quantity: qty,
          order_type: "MARKET",
          product_type: product_type,
          validity: "DAY",
          correlation_id: normalized_id,
          disclosed_quantity: 0
        }

        payload[:price] = price if price.present?

        order = DhanHQ::Models::Order.create(payload)

        remember(normalized_id)
        order
      end

      def sell_market!(seg:, sid:, qty:, client_order_id:)
        normalized_id = normalize_client_order_id(client_order_id)
        return if duplicate?(normalized_id)

        # Validate required parameters
        unless seg && sid && qty && normalized_id
          Rails.logger.error("[Orders] Missing required parameters: seg=#{seg}, sid=#{sid}, qty=#{qty}, client_order_id=#{client_order_id}")
          return nil
        end

        if normalized_id.present? && normalized_id != client_order_id
          Rails.logger.warn("[Orders] client_order_id truncated to '#{normalized_id}' (was '#{client_order_id}')")
        end

        Rails.logger.info("[Orders] Placing SELL order: seg=#{seg}, sid=#{sid}, qty=#{qty}, client_order_id=#{normalized_id}")

        order = DhanHQ::Models::Order.create(
          transaction_type: "SELL",
          exchange_segment: seg,
          security_id: sid,
          quantity: qty,
          order_type: "MARKET",
          product_type: "INTRADAY",
          validity: "DAY",
          correlation_id: normalized_id,
          disclosed_quantity: 0
        )
        remember(normalized_id)
        order
      end

      private

      def duplicate?(client_order_id)
        return false if client_order_id.blank?

        Rails.cache.read("coid:#{client_order_id}").present?
      end

      def remember(client_order_id)
        return if client_order_id.blank?

        Rails.cache.write("coid:#{client_order_id}", true, expires_in: 20.minutes)
      end

      def normalize_client_order_id(client_order_id)
        return if client_order_id.blank?

        value = client_order_id.to_s.strip
        return if value.blank?
        return value if value.length <= 30

        digest = Digest::SHA1.hexdigest(value)[0, 6]
        base = value[0, 23]
        "#{base}-#{digest}"
      end
    end
  end
end
