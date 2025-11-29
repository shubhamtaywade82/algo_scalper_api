# frozen_string_literal: true

require 'timeout'
require 'net/http'

class Orders::GatewayLive < Orders::Gateway
  RETRY_COUNT   = 3
  RETRY_BACKOFF = 0.25
  API_TIMEOUT   = 8

  # ------------ EXIT -----------------
  def exit_market(tracker)
    # Generate unique client order ID with random component to prevent collisions
    # Format: AS-EXIT-{security_id}-{timestamp}-{random}
    coid = "AS-EXIT-#{tracker.security_id}-#{Time.now.to_i}-#{SecureRandom.hex(2)}"

    order = Orders::Placer.exit_position!(
      seg: tracker.segment,
      sid: tracker.security_id,
      client_order_id: coid
    )

    return { success: true } if order

    { success: false, error: 'exit failed' }
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

  # ------------ POSITION SNAPSHOT ----
  def position(segment:, security_id:)
    positions = fetch_positions
    pos = positions.find do |p|
      p.security_id.to_s == security_id.to_s &&
        p.exchange_segment.to_s == segment.to_s
    end

    return nil unless pos

    {
      qty: pos.net_qty.to_i,
      avg_price: BigDecimal(pos.cost_price.to_s),
      product_type: pos.product_type,
      exchange_segment: pos.exchange_segment,
      position_type: pos.position_type,
      trading_symbol: pos.trading_symbol
    }
  end

  # ------------ WALLET ---------------
  def wallet_snapshot
    funds = DhanHQ::Models::FundLimit.fetch
    { cash: funds.available, utilized: funds.utilized, margin: funds.margin }
  rescue StandardError => e
    Rails.logger.error("[GatewayLive] wallet snapshot failed: #{e.message}")
    {}
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
    rescue Timeout::Error, Net::TimeoutError, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
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
    "AS-#{prefix}-#{sid}-#{Time.now.to_i}-#{SecureRandom.hex(2)}"
  end
end
