# frozen_string_literal: true

require 'digest'

module Orders
  class Placer
    # Valid tradable segments per DhanHQ API documentation
    # Indices (IDX_I, BSE_IDX, NSE_IDX) are NOT tradable - they are reference values only
    # NSE: NSE_EQ (Equity Cash), NSE_FNO (Futures & Options), NSE_CURRENCY (Currency)
    # BSE: BSE_EQ (Equity Cash), BSE_FNO (Futures & Options), BSE_CURRENCY (Currency)
    # MCX: MCX_COMM (Commodity)
    VALID_TRADABLE_SEGMENTS = %w[
      NSE_EQ
      NSE_FNO
      NSE_CURRENCY
      BSE_EQ
      BSE_FNO
      BSE_CURRENCY
      MCX_COMM
    ].freeze

    class << self
      def buy_market!(seg:, sid:, qty:, client_order_id:, product_type: 'INTRADAY', price: nil,
                      target_price: nil, stop_loss_price: nil, trailing_jump: nil)
        normalized_id = normalize_client_order_id(client_order_id)
        return nil if duplicate?(normalized_id)

        unless seg && sid && qty && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for buy_market!: seg=#{seg}, sid=#{sid}, qty=#{qty}, client_order_id=#{client_order_id}")
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable. Valid segments: #{VALID_TRADABLE_SEGMENTS.join(', ')}")
          return nil
        end

        payload = {
          dhanClientId: DhanHQ.configuration.client_id || ENV['DHANHQ_CLIENT_ID'] || ENV.fetch('CLIENT_ID', nil),
          transactionType: 'BUY',
          exchangeSegment: seg,
          securityId: sid.to_s,
          quantity: qty.to_i,
          orderType: 'MARKET',
          productType: product_type,
          validity: 'DAY',
          correlationId: normalized_id,
          disclosedQuantity: 0
        }
        payload[:price] = price if price.present?
        payload[:boProfitValue] = target_price if target_price.present?
        payload[:boStopLossValue] = stop_loss_price if stop_loss_price.present?

        Rails.logger.info("[Orders::Placer] BUY payload: #{payload.inspect}")

        if order_placement_enabled?
          begin
            order = DhanHQ::Models::Order.create(payload)
            Rails.logger.info("[Orders::Placer] BUY response: #{order.inspect}")
          rescue StandardError => e
            Rails.logger.error("[Orders::Placer] BUY failed: #{e.class} - #{e.message}")
            order = nil
          end
        else
          Rails.logger.debug('[Orders::Placer] BUY dry-run disabled order placement')
          order = nil
        end

        remember(normalized_id)
        order
      end

      def sell_market!(seg:, sid:, qty:, client_order_id:, product_type: nil)
        normalized_id = normalize_client_order_id(client_order_id)
        return nil if duplicate?(normalized_id)

        unless seg && sid && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for sell_market!: seg=#{seg}, sid=#{sid}, client_order_id=#{client_order_id}")
          return nil
        end

        position = fetch_position_details(sid)
        actual_segment = position ? position[:exchange_segment] : seg

        unless segment_tradable?(actual_segment)
          Rails.logger.error("[Orders::Placer] Segment #{actual_segment} is not tradable. Valid segments: #{VALID_TRADABLE_SEGMENTS.join(', ')}")
          return nil
        end

        actual_qty = if position && position[:net_qty].to_i.positive?
                       position[:net_qty]
                     else
                       qty
                     end

        payload = {
          dhanClientId: DhanHQ.configuration.client_id || ENV['DHANHQ_CLIENT_ID'] || ENV.fetch('CLIENT_ID', nil),
          transactionType: 'SELL',
          exchangeSegment: position ? position[:exchange_segment] : seg,
          securityId: sid.to_s,
          quantity: actual_qty.to_i,
          orderType: 'MARKET',
          productType: position ? position[:product_type] : product_type,
          validity: 'DAY',
          disclosedQuantity: 0,
          correlationId: normalized_id
        }

        Rails.logger.info("[Orders::Placer] SELL payload: #{payload.inspect}")

        if order_placement_enabled?
          begin
            order = DhanHQ::Models::Order.create(payload)
            Rails.logger.info("[Orders::Placer] SELL response: #{order.inspect}")
          rescue StandardError => e
            Rails.logger.error("[Orders::Placer] SELL failed: #{e.class} - #{e.message}")
            order = nil
          end
        else
          Rails.logger.debug('[Orders::Placer] SELL dry-run disabled order placement')
          order = nil
        end

        remember(normalized_id)
        order
      end

      def exit_position!(seg:, sid:, client_order_id:)
        normalized_id = normalize_client_order_id(client_order_id)
        return nil if duplicate?(normalized_id)

        unless sid && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for exit_position!: sid=#{sid}, client_order_id=#{client_order_id}")
          return nil
        end

        position_details = fetch_position_details(sid)
        unless position_details
          Rails.logger.error("[Orders::Placer] Cannot find position to exit for sid=#{sid}")
          return nil
        end

        actual_qty = position_details[:net_qty]
        actual_segment = position_details[:exchange_segment]
        position_type = position_details[:position_type]

        unless segment_tradable?(actual_segment)
          Rails.logger.error("[Orders::Placer] Segment #{actual_segment} is not tradable. Valid segments: #{VALID_TRADABLE_SEGMENTS.join(', ')}")
          return nil
        end

        transaction_type = case position_type
                           when 'LONG' then 'SELL'
                           when 'SHORT' then 'BUY'
                           else
                             Rails.logger.error("[Orders::Placer] Unknown position type #{position_type}")
                             return nil
                           end

        payload = {
          dhanClientId: DhanHQ.configuration.client_id || ENV['DHANHQ_CLIENT_ID'] || ENV.fetch('CLIENT_ID', nil),
          transactionType: transaction_type,
          exchangeSegment: actual_segment,
          securityId: sid.to_s,
          quantity: actual_qty.to_i,
          orderType: 'MARKET',
          productType: position_details[:product_type],
          validity: 'DAY',
          disclosedQuantity: 0,
          correlationId: normalized_id
        }

        Rails.logger.info("[Orders::Placer] EXIT payload: #{payload.inspect}")

        if order_placement_enabled?
          begin
            order = DhanHQ::Models::Order.create(payload)
            Rails.logger.info("[Orders::Placer] EXIT response: #{order.inspect}")
          rescue StandardError => e
            Rails.logger.error("[Orders::Placer] EXIT failed: #{e.class} - #{e.message}")
            order = nil
          end
        else
          Rails.logger.debug('[Orders::Placer] EXIT dry-run disabled order placement')
          order = nil
        end

        remember(normalized_id)
        order
      end

      private

      def fetch_position_details(security_id)
        positions = DhanHQ::Models::Position.active
        pos = positions.find { |p| p.security_id.to_s == security_id.to_s }
        return nil unless pos

        {
          product_type: pos.respond_to?(:product_type) ? pos.product_type : pos[:product_type],
          net_qty: pos.respond_to?(:net_qty) ? pos.net_qty.to_i : (pos[:net_qty] || pos[:quantity]).to_i,
          exchange_segment: pos.respond_to?(:exchange_segment) ? pos.exchange_segment : pos[:exchange_segment],
          position_type: pos.respond_to?(:position_type) ? pos.position_type : (pos[:position_type] || 'LONG'),
          buy_avg: pos.respond_to?(:buy_avg) ? pos.buy_avg : nil,
          trading_symbol: pos.respond_to?(:trading_symbol) ? pos.trading_symbol : pos[:trading_symbol]
        }
      rescue StandardError => e
        Rails.logger.error("[Orders::Placer] fetch_position_details error: #{e.class} - #{e.message}")
        nil
      end

      def order_placement_enabled?
        cfg = begin
          Rails.application.config.x.dhanhq
        rescue StandardError
          nil
        end
        (cfg && cfg.enable_order_logging == true) || AlgoConfig.fetch.dig(:dhanhq, :enable_orders) == true
      rescue StandardError
        false
      end

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

      def segment_tradable?(segment)
        return false if segment.blank?

        VALID_TRADABLE_SEGMENTS.include?(segment.to_s.upcase)
      end
    end
  end
end
