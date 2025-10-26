# frozen_string_literal: true

require 'digest'

module Orders
  class Placer
    class << self
      def buy_market!(seg:, sid:, qty:, client_order_id:, product_type: 'INTRADAY', price: nil,
                      target_price: nil, stop_loss_price: nil, trailing_jump: nil) # rubocop:disable Lint/UnusedMethodArgument
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
          transaction_type: 'BUY',
          exchange_segment: seg,
          security_id: sid.to_s,
          quantity: qty,
          order_type: 'MARKET',
          product_type: product_type,
          validity: 'DAY',
          correlation_id: normalized_id,
          disclosed_quantity: 0
        }

        payload[:price] = price if price.present?

        # Log order payload
        Rails.logger.info("[Orders] BUY Order Payload: #{payload.inspect}")

        # Only place order if ENABLE_ORDER flag is set
        if order_placement_enabled?
          begin
            order = DhanHQ::Models::Order.create(payload)
            Rails.logger.info('[Orders] BUY Order placed successfully')
          rescue StandardError => e
            Rails.logger.error("[Orders] Failed to place order: #{e.class} - #{e.message}")
            order = nil
          end
        else
          Rails.logger.info('[Orders] BUY Order NOT placed - ENABLE_ORDER=false (dry run mode)')
          order = nil
        end

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

        # Fetch complete position details from DhanHQ to ensure exact matching
        position_details = fetch_position_details(sid)
        unless position_details
          Rails.logger.error("[Orders] Cannot fetch position details for security_id #{sid} - aborting sell order")
          return nil
        end

        # Use position's actual quantity instead of passed qty parameter
        actual_qty = position_details[:net_qty]
        actual_segment = position_details[:exchange_segment]

        # Validate that the position exists and has quantity
        if actual_qty.to_i <= 0
          Rails.logger.error("[Orders] Position has zero or negative quantity (#{actual_qty}) for security_id #{sid} - aborting sell order")
          return nil
        end

        # Validate position type for proper exit
        position_type = position_details[:position_type]
        if position_type == 'SHORT'
          Rails.logger.error("[Orders] Position is SHORT (#{position_type}) - should use BUY order to cover, not SELL order")
          return nil
        elsif position_type != 'LONG'
          Rails.logger.warn("[Orders] Unknown position type: #{position_type} - proceeding with SELL order")
        end

        Rails.logger.info("[Orders] Placing SELL order: seg=#{actual_segment}, sid=#{sid}, qty=#{actual_qty}, client_order_id=#{normalized_id}, product_type=#{position_details[:product_type]}, position_type=#{position_type}")

        payload = {
          transaction_type: 'SELL',
          exchange_segment: actual_segment,
          security_id: sid.to_s,
          quantity: actual_qty,
          order_type: 'MARKET',
          product_type: position_details[:product_type],
          validity: 'DAY',
          disclosed_quantity: 0
        }

        # Log order payload
        Rails.logger.info("[Orders] SELL Order Payload: #{payload.inspect}")

        # Only place order if ENABLE_ORDER flag is set
        if order_placement_enabled?
          begin
            order = DhanHQ::Models::Order.create(payload)
            Rails.logger.info('[Orders] SELL Order placed successfully')
          rescue StandardError => e
            Rails.logger.error("[Orders] Failed to place order: #{e.class} - #{e.message}")
            order = nil
          end
        else
          Rails.logger.info('[Orders] SELL Order NOT placed - ENABLE_ORDER=false (dry run mode)')
          order = nil
        end
        remember(normalized_id)
        order
      end

      def exit_position!(seg:, sid:, client_order_id:)
        normalized_id = normalize_client_order_id(client_order_id)
        return if duplicate?(normalized_id)

        # Validate required parameters
        unless seg && sid && normalized_id
          Rails.logger.error("[Orders] Missing required parameters: seg=#{seg}, sid=#{sid}, client_order_id=#{client_order_id}")
          return nil
        end

        # Fetch complete position details from DhanHQ
        position_details = fetch_position_details(sid)
        unless position_details
          Rails.logger.error("[Orders] Cannot fetch position details for security_id #{sid} - aborting exit order")
          return nil
        end

        actual_qty = position_details[:net_qty]
        actual_segment = position_details[:exchange_segment]
        position_type = position_details[:position_type]

        # Validate that the position exists and has quantity
        if actual_qty.to_i <= 0
          Rails.logger.error("[Orders] Position has zero or negative quantity (#{actual_qty}) for security_id #{sid} - aborting exit order")
          return nil
        end

        # Determine transaction type based on position type
        transaction_type = case position_type
                           when 'LONG'
                             'SELL'
                           when 'SHORT'
                             'BUY'
                           else
                             Rails.logger.error("[Orders] Unknown position type: #{position_type} - cannot determine exit transaction type")
                             return nil
                           end

        Rails.logger.info("[Orders] Placing EXIT order: #{transaction_type} #{actual_segment}:#{sid} qty=#{actual_qty}, product_type=#{position_details[:product_type]}, position_type=#{position_type}")

        payload = {
          transaction_type: transaction_type,
          exchange_segment: actual_segment,
          security_id: sid.to_s,
          quantity: actual_qty,
          order_type: 'MARKET',
          product_type: position_details[:product_type],
          validity: 'DAY',
          disclosed_quantity: 0
        }

        # Log order payload
        Rails.logger.info("[Orders] EXIT Order Payload: #{payload.inspect}")

        # Only place order if ENABLE_ORDER flag is set
        if order_placement_enabled?
          begin
            order = DhanHQ::Models::Order.create(payload)
            Rails.logger.info('[Orders] EXIT Order placed successfully')
          rescue StandardError => e
            Rails.logger.error("[Orders] Failed to place exit order: #{e.class} - #{e.message}")
            order = nil
          end
        else
          Rails.logger.info('[Orders] EXIT Order NOT placed - ENABLE_ORDER=false (dry run mode)')
          order = nil
        end

        remember(normalized_id)
        order
      end

      private

      def fetch_position_details(security_id)
        positions = DhanHQ::Models::Position.active
        position = positions.find { |p| p.security_id.to_s == security_id.to_s }

        if position
          Rails.logger.debug { "[Orders] Found position for #{security_id}: product_type=#{position.product_type}, net_qty=#{position.net_qty}" }
          {
            product_type: position.product_type,
            net_qty: position.net_qty,
            exchange_segment: position.exchange_segment,
            position_type: position.position_type,
            buy_avg: position.buy_avg,
            trading_symbol: position.trading_symbol
          }
        else
          Rails.logger.warn("[Orders] No active position found for security_id #{security_id}")
          nil
        end
      rescue StandardError => e
        Rails.logger.error("[Orders] Error fetching position for #{security_id}: #{e.class} - #{e.message}")
        nil
      end

      def order_placement_enabled?
        config = Rails.application.config.x.dhanhq
        config&.enable_order_logging == true
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
    end
  end
end
