# frozen_string_literal: true

require 'timeout'
require 'net/http'

module Orders
  class GatewayLive < Orders::Gateway
    RETRY_COUNT   = 3
    RETRY_BACKOFF = 0.25
    API_TIMEOUT   = 8

    # ------------ EXIT -----------------
    # Places an exit market order for the tracker.
    # @param tracker [PositionTracker]
    # @param client_order_id [String, nil] deterministic idempotency key for retries
    # @return [Hash] normalized result with :success and optional :order_id/:status
    def exit_market(tracker, client_order_id: nil)
      coid = client_order_id.presence || generate_client_order_id('EXIT', tracker.security_id)

      order = Orders::Placer.exit_position!(
        seg: tracker.segment,
        sid: tracker.security_id,
        client_order_id: coid
      )

      normalize_exit_response(order, client_order_id: coid)
    end

    # ------------ ENTRY (BUY/SELL) -----
    def place_market(side:, segment:, security_id:, qty:, meta: {})
      validate_side!(side)
      coid = meta[:client_order_id] || generate_client_order_id(side, security_id)

      with_retries do
        if side.to_s.downcase == 'buy'
          Orders::Placer.buy_market!(
            seg: segment,
            sid: security_id,
            qty: qty,
            client_order_id: coid,
            price: meta[:price],
            target_price: meta[:target_price],
            stop_loss_price: meta[:stop_loss_price],
            product_type: meta[:product_type]
          )
        else
          Orders::Placer.sell_market!(
            seg: segment,
            sid: security_id,
            qty: qty,
            client_order_id: coid,
            product_type: meta[:product_type]
          )
        end
      end
    end

    # ------------ WALLET ---------------
    def wallet_snapshot
      funds = DhanHQ::Models::Funds.fetch
      {
        cash: funds.available_balance,
        utilized: funds.utilized_amount,
        margin: funds.respond_to?(:margin) ? funds.margin : 0
      }
    rescue StandardError => e
      Rails.logger.error("[GatewayLive] wallet snapshot failed: #{e.message}")
      {}
    end

    def cancel_order(order_id)
      with_retries do
        order = DhanHQ::Models::Order.find(order_id)
        order.cancel
      end
    rescue StandardError => e
      Rails.logger.error("[GatewayLive] cancel_order failed for #{order_id}: #{e.class} - #{e.message}")
      raise
    end

    # Exit by segment/security_id (used when no tracker is available).
    # Prefer exit_market(tracker) when a PositionTracker exists.
    def flat_position(segment:, security_id:)
      Orders::Placer.exit_position!(
        seg: segment,
        sid: security_id,
        client_order_id: generate_client_order_id('EXIT', security_id)
      )
    end

    # Fetch position summary for segment/security_id from DhanHQ Position API.
    # @return [Hash, nil] { qty:, avg_price:, upnl:, rpnl:, last_ltp: } or nil on error
    def position(segment:, security_id:)
      positions = fetch_positions
      pos = positions.find { |p| p.security_id.to_s == security_id.to_s && p.exchange_segment.to_s == segment.to_s }
      return nil unless pos

      entry_price = pos.respond_to?(:buy_avg) ? BigDecimal(pos.buy_avg.to_s) : nil
      qty = pos.respond_to?(:net_qty) ? pos.net_qty.to_i : 0
      tick = Live::TickQuery.for_security(segment: segment, security_id: security_id.to_s)
      ltp = tick&.ltp

      upnl = if entry_price && ltp && qty != 0
               (BigDecimal(ltp.to_s) - entry_price) * qty
             else
               BigDecimal(0)
             end

      {
        qty: qty,
        avg_price: entry_price || BigDecimal(0),
        upnl: upnl,
        rpnl: BigDecimal(0),
        last_ltp: ltp ? BigDecimal(ltp.to_s) : (entry_price || BigDecimal(0))
      }
    rescue StandardError => e
      Rails.logger.error("[GatewayLive] position failed: #{e.message}")
      nil
    end

    private

    def validate_side!(side)
      raise 'invalid side' unless %w[buy sell].include?(side.to_s)
    end

    def with_retries
      attempts = 0
      begin
        attempts += 1
        Timeout.timeout(API_TIMEOUT) { return yield }
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        # Retryable errors: network/timeout issues
        Rails.logger.warn("[GatewayLive] attempt #{attempts} failed (retryable) #{e.class}: #{e.message}")
        raise if attempts >= RETRY_COUNT

        sleep RETRY_BACKOFF * attempts
        retry
      rescue StandardError => e
        # Non-retryable errors: validation, business logic, etc.
        Rails.logger.error("[GatewayLive] attempt #{attempts} failed (non-retryable) #{e.class}: #{e.message}")
        raise
      end
    end

    def fetch_positions
      DhanHQ::Models::Position.active
    rescue StandardError => e
      Rails.logger.error("[GatewayLive] fetch_positions error: #{e.message}")
      []
    end

    def generate_client_order_id(prefix, sid)
      # Generate unique client order ID with random component to prevent collisions
      # Format: AS-{prefix}-{security_id}-{timestamp}-{random}
      "AS-#{prefix}-#{sid}-#{Time.current.to_i}-#{SecureRandom.hex(2)}"
    end

    def normalize_exit_response(order, client_order_id:)
      if already_closed_or_duplicate?(order)
        return {
          success: true,
          status: :already_closed,
          order_id: extract_order_id(order),
          client_order_id: client_order_id
        }
      end

      return { success: true, status: :accepted, order_id: extract_order_id(order), client_order_id: client_order_id } if order.present?

      { success: false, status: :failed, error: 'exit failed', client_order_id: client_order_id }
    end

    def already_closed_or_duplicate?(order)
      # DhanHQ payloads observed in this codebase use error/message text like
      # 'position not found' and 'duplicate'; re-verify these tokens on broker API changes.
      return false unless order.is_a?(Hash)

      code = (order[:error_code] || order['error_code']).to_s.downcase
      message = (order[:message] || order['message'] || order[:error] || order['error']).to_s.downcase

      [code, message].any? do |value|
        value.include?('already') || value.include?('closed') ||
          value.include?('position not found') || value.include?('duplicate')
      end
    end

    def extract_order_id(order)
      return order.order_id if order.respond_to?(:order_id)
      return order[:order_id] || order['order_id'] if order.is_a?(Hash)

      nil
    end
  end
end
