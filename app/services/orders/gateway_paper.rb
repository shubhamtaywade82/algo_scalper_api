# frozen_string_literal: true

class Orders::GatewayPaper < Orders::Gateway
  def exit_market(tracker)
    ltp = Live::TickCache.ltp(tracker.segment, tracker.security_id) ||
          tracker.entry_price

    exit_price = BigDecimal(ltp.to_s)

    # Return success with exit_price - let ExitEngine update tracker (consistent with live mode)
    # This ensures single source of truth and prevents double updates
    { success: true, exit_price: exit_price }
  end

  def place_market(side:, segment:, security_id:, qty:, meta: {})
    tracker = PositionTracker.active_for(segment, security_id)
    tracker ||= PositionTracker.create!(
      instrument_id: nil,
      order_no: "PAPER-#{SecureRandom.hex(3)}",
      security_id: security_id.to_s,
      symbol: meta[:symbol] || security_id.to_s,
      segment: segment,
      side: side.to_s.upcase,
      status: 'active',
      quantity: qty,
      avg_price: meta[:price] || 0
    )

    { success: true, paper: true, tracker_id: tracker.id }
  rescue StandardError => e
    Rails.logger.error("[GatewayPaper] place_market failed for #{segment}-#{security_id}: #{e.class} - #{e.message}")
    { success: false, error: e.message, paper: true }
  end

  def position(segment:, security_id:)
    tracker = PositionTracker.active_for(segment, security_id)
    return nil unless tracker

    # Return consistent format with GatewayLive for better compatibility
    {
      qty: tracker.quantity,
      avg_price: tracker.avg_price,
      product_type: nil, # Paper trading doesn't have product_type
      exchange_segment: tracker.segment,
      position_type: tracker.side == 'BUY' ? 'LONG' : 'SHORT',
      trading_symbol: tracker.symbol,
      status: tracker.status # Additional field for paper mode
    }
  end

  def wallet_snapshot
    balance = AlgoConfig.fetch.dig(:paper_trading, :balance) || 100_000
    { cash: balance, equity: balance, mtm: 0, exposure: 0 }
  rescue StandardError => e
    Rails.logger.error("[GatewayPaper] wallet_snapshot failed: #{e.class} - #{e.message}")
    { cash: 100_000, equity: 100_000, mtm: 0, exposure: 0 } # Return default on error
  end
end
