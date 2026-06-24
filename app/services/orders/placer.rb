# frozen_string_literal: true

require "digest"
require "token_bucket"

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
      def buy_market!(seg:, sid:, qty:, client_order_id:, product_type: "NORMAL", price: nil,
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
          transaction_type: DhanHQ::Constants::TransactionType::BUY,
          exchange_segment: seg,
          security_id: sid.to_s,
          quantity: qty.to_i,
          order_type: DhanHQ::Constants::OrderType::MARKET,
          product_type: product_type,
          validity: DhanHQ::Constants::Validity::DAY,
          correlation_id: normalized_id,
          disclosed_quantity: 0
        }
        # DhanHQ 2.6.x PlaceOrderContract: MARKET orders must not send price
        payload[:bo_profit_value] = target_price if target_price.present?
        payload[:bo_stop_loss_value] = stop_loss_price if stop_loss_price.present?

        Rails.logger.info("[Orders::Placer] BUY payload: #{payload.inspect}")

        if order_placement_enabled?
          order = with_order_rate_limit(context: "orders.buy_market") do
            DhanHQ::Models::Order.create(payload)
          end
          Rails.logger.info("[Orders::Placer] BUY response: #{order.inspect}") if order
        else
          Rails.logger.warn("[Orders::Placer] BUY blocked because PLACE_ORDER is not enabled")
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
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
          exchange_segment: position ? position[:exchange_segment] : seg,
          security_id: sid.to_s,
          quantity: actual_qty.to_i,
          order_type: DhanHQ::Constants::OrderType::MARKET,
          product_type: position ? position[:product_type] : product_type,
          validity: DhanHQ::Constants::Validity::DAY,
          disclosed_quantity: 0,
          correlation_id: normalized_id
        }

        Rails.logger.info("[Orders::Placer] SELL payload: #{payload.inspect}")

        if order_placement_enabled?
          order = with_order_rate_limit(context: "orders.sell_market") do
            DhanHQ::Models::Order.create(payload)
          end
          Rails.logger.info("[Orders::Placer] SELL response: #{order.inspect}") if order
        else
          Rails.logger.warn("[Orders::Placer] SELL blocked because PLACE_ORDER is not enabled")
          order = nil
        end

        remember(normalized_id)
        order
      end

      def buy_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil if duplicate?(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for buy_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          return nil
        end

        payload = {
          transaction_type: DhanHQ::Constants::TransactionType::BUY,
          exchange_segment: seg,
          security_id: sid.to_s,
          quantity: qty.to_i,
          order_type: DhanHQ::Constants::OrderType::LIMIT,
          product_type: product_type,
          price: price.to_f.round(2),
          validity: DhanHQ::Constants::Validity::DAY,
          correlation_id: normalized_id,
          disclosed_quantity: 0
        }

        Rails.logger.info("[Orders::Placer] BUY LIMIT payload: #{payload.inspect}")

        if order_placement_enabled?
          order = with_order_rate_limit(context: "orders.buy_limit") do
            DhanHQ::Models::Order.create(payload)
          end
          Rails.logger.info("[Orders::Placer] BUY LIMIT response: #{order.inspect}") if order
        else
          Rails.logger.warn("[Orders::Placer] BUY LIMIT blocked because PLACE_ORDER is not enabled")
          order = OpenStruct.new(order_id: "MOCK_LIMIT_#{SecureRandom.hex(4).upcase}", status: "success")
        end

        remember(normalized_id)
        order
      end

      def buy_ioc_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil if duplicate?(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for buy_ioc_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          return nil
        end

        payload = {
          transaction_type: DhanHQ::Constants::TransactionType::BUY,
          exchange_segment: seg,
          security_id: sid.to_s,
          quantity: qty.to_i,
          order_type: DhanHQ::Constants::OrderType::LIMIT,
          product_type: product_type,
          price: price.to_f.round(2),
          validity: DhanHQ::Constants::Validity::IOC,
          correlation_id: normalized_id,
          disclosed_quantity: 0
        }

        Rails.logger.info("[Orders::Placer] BUY IOC LIMIT payload: #{payload.inspect}")

        if order_placement_enabled?
          order = with_order_rate_limit(context: "orders.buy_ioc_limit") do
            DhanHQ::Models::Order.create(payload)
          end
          Rails.logger.info("[Orders::Placer] BUY IOC LIMIT response: #{order.inspect}") if order
        else
          Rails.logger.warn("[Orders::Placer] BUY IOC LIMIT blocked because PLACE_ORDER is not enabled")
          order = OpenStruct.new(order_id: "MOCK_IOC_#{SecureRandom.hex(4).upcase}", status: "success")
        end

        remember(normalized_id)
        order
      end

      # Market order first; fall back to IOC limit if market returns nil (e.g. PLACE_ORDER disabled
      # or broker rejected). This keeps the entry pipeline resilient without changing live code paths.
      def buy_entry_with_fallback!(seg:, sid:, qty:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless seg && sid && qty && normalized_id

        order = buy_market!(seg: seg, sid: sid, qty: qty, client_order_id: normalized_id, product_type: product_type)
        return order if order

        Rails.logger.warn("[Orders::Placer] buy_market! returned nil for #{sid}; falling back to IOC limit")
        buy_ioc_limit!(seg: seg, sid: sid, qty: qty, client_order_id: normalized_id, product_type: product_type)
      rescue StandardError => e
        Rails.logger.warn("[Orders::Placer] buy_entry_with_fallback! market failed (#{e.class}); trying IOC limit")
        buy_ioc_limit!(seg: seg, sid: sid, qty: qty, client_order_id: normalized_id, product_type: product_type)
      end

      def sell_ioc_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil if duplicate?(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for sell_ioc_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          return nil
        end

        payload = {
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
          exchange_segment: seg,
          security_id: sid.to_s,
          quantity: qty.to_i,
          order_type: DhanHQ::Constants::OrderType::LIMIT,
          product_type: product_type,
          price: price.to_f.round(2),
          validity: DhanHQ::Constants::Validity::IOC,
          correlation_id: normalized_id,
          disclosed_quantity: 0
        }

        Rails.logger.info("[Orders::Placer] SELL IOC LIMIT payload: #{payload.inspect}")

        if order_placement_enabled?
          order = with_order_rate_limit(context: "orders.sell_ioc_limit") do
            DhanHQ::Models::Order.create(payload)
          end
          Rails.logger.info("[Orders::Placer] SELL IOC LIMIT response: #{order.inspect}") if order
        else
          Rails.logger.warn("[Orders::Placer] SELL IOC LIMIT blocked because PLACE_ORDER is not enabled")
          order = OpenStruct.new(order_id: "MOCK_IOC_#{SecureRandom.hex(4).upcase}", status: "success")
        end

        remember(normalized_id)
        order
      end

      def sell_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil if duplicate?(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for sell_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          return nil
        end

        payload = {
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
          exchange_segment: seg,
          security_id: sid.to_s,
          quantity: qty.to_i,
          order_type: DhanHQ::Constants::OrderType::LIMIT,
          product_type: product_type,
          price: price.to_f.round(2),
          validity: DhanHQ::Constants::Validity::DAY,
          correlation_id: normalized_id,
          disclosed_quantity: 0
        }

        Rails.logger.info("[Orders::Placer] SELL LIMIT payload: #{payload.inspect}")

        if order_placement_enabled?
          order = with_order_rate_limit(context: "orders.sell_limit") do
            DhanHQ::Models::Order.create(payload)
          end
          Rails.logger.info("[Orders::Placer] SELL LIMIT response: #{order.inspect}") if order
        else
          Rails.logger.warn("[Orders::Placer] SELL LIMIT blocked because PLACE_ORDER is not enabled")
          order = OpenStruct.new(order_id: "MOCK_LIMIT_#{SecureRandom.hex(4).upcase}", status: "success")
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
                           when "LONG" then "SELL"
                           when "SHORT" then "BUY"
                           else
          Rails.logger.error("[Orders::Placer] Unknown position type #{position_type}")
          return nil
                           end

        payload = {
          transaction_type: transaction_type,
          exchange_segment: actual_segment,
          security_id: sid.to_s,
          quantity: actual_qty.to_i,
          order_type: DhanHQ::Constants::OrderType::MARKET,
          product_type: position_details[:product_type],
          validity: DhanHQ::Constants::Validity::DAY,
          disclosed_quantity: 0,
          correlation_id: normalized_id
        }

        Rails.logger.info("[Orders::Placer] EXIT payload: #{payload.inspect}")

        if order_placement_enabled?
          order = with_order_rate_limit(context: "orders.exit_position") do
            DhanHQ::Models::Order.create(payload)
          end
          Rails.logger.info("[Orders::Placer] EXIT response: #{order.inspect}") if order
        else
          Rails.logger.warn("[Orders::Placer] EXIT blocked because PLACE_ORDER is not enabled")
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
          position_type: pos.respond_to?(:position_type) ? pos.position_type : (pos[:position_type] || "LONG"),
          buy_avg: pos.respond_to?(:buy_avg) ? pos.buy_avg : nil,
          trading_symbol: pos.respond_to?(:trading_symbol) ? pos.trading_symbol : pos[:trading_symbol]
        }
      rescue StandardError => e
        Rails.logger.error("[Orders::Placer] fetch_position_details error: #{e.class} - #{e.message}")
        nil
      end

      def with_order_rate_limit(context: nil, &)
        rate_limiter.consume!(&)
      rescue TokenBucket::RateLimited => e
        Rails.logger.warn("[Orders::Placer] rate limited: #{e.message}")
        nil
      end

      def with_token_auto_heal(context:, &)
        retried = false
        with_order_rate_limit(&)
      rescue StandardError => e
        Rails.logger.error("[Orders::Placer] #{context} failed: #{e.class} - #{e.message}")

        unless DhanhqErrorHandler.token_expired?(e)
          return nil
        end

        if retried
          Rails.logger.error("[Orders::Placer] #{context} retry failed: #{e.class} - #{e.message}")
          return nil
        end

        Rails.logger.warn("[Orders::Placer] #{context} unauthorized; refreshing token and retrying once")
        Dhan::TokenManager.refresh! if defined?(Dhan::TokenManager)
        retried = true
        retry
      end

      def order_placement_enabled?
        ENV["PLACE_ORDER"].to_s.casecmp("true").zero?
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

      def rate_limiter
        @rate_limiter ||= TokenBucket.new(rate: 10, per: 1.second)
      end

      def segment_tradable?(segment)
        return false if segment.blank?

        VALID_TRADABLE_SEGMENTS.include?(segment.to_s.upcase)
      end
    end
  end
end
