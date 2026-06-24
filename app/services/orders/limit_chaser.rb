# frozen_string_literal: true

module Orders
  # Service that implements midpoint-based limit chasing for buy orders (entries).
  class LimitChaser
    FILLED_STATUSES = %w[TRADED COMPLETE FILLED].freeze
    CANCELLED_STATUSES = %w[CANCELLED REJECTED].freeze

    class << self
      def place_and_chase(side:, segment:, security_id:, qty:, meta:, gateway:)
        # 1. Check if limit chasing is enabled in config
        config = AlgoConfig.fetch.dig(:risk, :execution, :limit_chasing) ||
                 AlgoConfig.fetch.dig(:options_buying, :execution, :limit_chasing) || {}

        enabled = config[:enabled] == true
        unless enabled
          return gateway.send(:place_market_direct, side: side, segment: segment, security_id: security_id, qty: qty, meta: meta)
        end

        # 2. Check if order placement is enabled or if it's paper trading
        unless Orders::Placer.send(:order_placement_enabled?)
          # In dry-run or paper mode, immediately return simulated order response
          return gateway.send(:place_market_direct, side: side, segment: segment, security_id: security_id, qty: qty, meta: meta)
        end

        # 3. Get bidding/asking info
        tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
        bid = tick&.bid&.to_f
        ask = tick&.ask&.to_f

        # If bid/ask not available, fall back to market order
        if bid.nil? || ask.nil? || bid.zero? || ask.zero?
          Rails.logger.warn("[LimitChaser] Bid/Ask not available for #{security_id}. Falling back to market order.")
          return gateway.send(:place_market_direct, side: side, segment: segment, security_id: security_id, qty: qty, meta: meta)
        end

        # 4. Calculate initial midpoint
        midpoint = ((bid + ask) / 2.0).round(2)
        Rails.logger.info("[LimitChaser] Starting limit chasing for #{security_id} at midpoint #{midpoint} (bid: #{bid}, ask: #{ask})")

        # 5. Place initial limit order
        client_order_id = meta[:client_order_id] || "CHASE_#{SecureRandom.hex(4).upcase}"
        order = Orders::Placer.buy_limit!(
          seg: segment,
          sid: security_id,
          qty: qty,
          price: midpoint,
          client_order_id: client_order_id,
          product_type: meta[:product_type] || "NORMAL"
        )

        return nil unless order

        order_id = order.respond_to?(:order_id) ? order.order_id : (order[:order_id] || order["order_id"])
        return order unless order_id # If no order_id (mock), return order

        # 6. Chase loop
        max_chase_seconds = (config[:max_chase_seconds] || 15).to_f
        tick_interval = (config[:tick_interval_seconds] || 2).to_f
        fallback_to_market = config[:fallback_to_market] != false

        start_time = Time.current
        current_limit_price = midpoint
        current_order_id = order_id

        while (Time.current - start_time) < max_chase_seconds
          sleep(tick_interval)

          # Check order status
          begin
            order_status_obj = DhanHQ::Models::Order.find(current_order_id)
            status = order_status_obj&.order_status.to_s.upcase

            if FILLED_STATUSES.include?(status)
              Rails.logger.info("[LimitChaser] Order #{current_order_id} filled successfully!")
              return order_status_obj
            elsif CANCELLED_STATUSES.include?(status)
              Rails.logger.warn("[LimitChaser] Order #{current_order_id} was #{status}. Exiting chase.")
              return order_status_obj
            end
          rescue StandardError => e
            Rails.logger.error("[LimitChaser] Error fetching status for #{current_order_id}: #{e.message}")
          end

          # Get new bid/ask
          new_tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
          new_bid = new_tick&.bid&.to_f
          new_ask = new_tick&.ask&.to_f

          next if new_bid.nil? || new_ask.nil? || new_bid.zero? || new_ask.zero?

          new_midpoint = ((new_bid + new_ask) / 2.0).round(2)

          # If midpoint moved, cancel and replace
          next unless new_midpoint != current_limit_price
          Rails.logger.info("[LimitChaser] Midpoint moved from #{current_limit_price} to #{new_midpoint}. Replacing order.")

          # Cancel old order
          begin
            DhanHQ::Models::Order.find(current_order_id).cancel
          rescue StandardError => e
            Rails.logger.warn("[LimitChaser] Failed to cancel order #{current_order_id}: #{e.message}")
          end

          # Place new limit order
          new_client_id = "CHASE_#{SecureRandom.hex(4).upcase}"
          new_order = Orders::Placer.buy_limit!(
            seg: segment,
            sid: security_id,
            qty: qty,
            price: new_midpoint,
            client_order_id: new_client_id,
            product_type: meta[:product_type] || "NORMAL"
          )

          if new_order
            current_order_id = new_order.respond_to?(:order_id) ? new_order.order_id : (new_order[:order_id] || new_order["order_id"])
            current_limit_price = new_midpoint
            order = new_order
          else
            Rails.logger.error("[LimitChaser] Failed to place replacement limit order.")
          end
        end

        # 7. Fallback if still not filled
        Rails.logger.warn("[LimitChaser] Chase timeout reached for #{security_id}.")

        # Cancel the last active limit order
        begin
          DhanHQ::Models::Order.find(current_order_id).cancel
        rescue StandardError => e
          Rails.logger.warn("[LimitChaser] Failed to cancel final limit order #{current_order_id}: #{e.message}")
        end

        if fallback_to_market
          Rails.logger.info("[LimitChaser] Falling back to market order for #{security_id}")
          market_client_id = "CHASE_MKT_#{SecureRandom.hex(4).upcase}"
          return gateway.send(:place_market_direct,
                              side: side,
                              segment: segment,
                              security_id: security_id,
                              qty: qty,
                              meta: meta.merge(client_order_id: market_client_id))
        end

        order
      end
    end
  end
end
