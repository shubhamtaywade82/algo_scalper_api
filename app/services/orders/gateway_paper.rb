# frozen_string_literal: true

module Orders
  class GatewayPaper < Orders::Gateway
    def exit_market(tracker, client_order_id: nil)
      ltp = Live::TickQuery.ltp_for(tracker) || tracker.entry_price

      exit_price = BigDecimal(ltp.to_s)
      coid = client_order_id || "PAPER-EXIT-#{tracker.id}"

      # Return normalized shape with exit_price - ExitEngine remains the single source of truth.
      {
        success: true,
        exit_price: exit_price,
        order_id: coid,
        client_order_id: coid,
        status: :accepted,
        paper: true
      }
    end

    def place_market(side:, segment:, security_id:, qty:, meta: {})
      order_no = meta[:client_order_id] || "PAPER-#{SecureRandom.hex(3)}"

      # Simulate broker ack only; domain services own tracker persistence.
      { success: true, order_id: order_no, paper: true }
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] place_market failed for #{segment}-#{security_id}: #{e.class} - #{e.message}")
      { success: false, error: e.message, paper: true }
    end

    # Paper wallet is the double-entry ledger (Ledger::WalletReader) — single
    # source of truth: seed + all-time realized PnL - brokerage - premium locked
    # in open positions. (Legacy derived snapshot only counted today's PnL.)
    def wallet_snapshot
      Ledger::WalletReader.snapshot(mode: :paper)
                          .slice(:cash, :equity, :mtm, :exposure, :utilized, :margin)
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] wallet_snapshot failed: #{e.class} - #{e.message}")
      { cash: 100_000, equity: 100_000, mtm: 0, exposure: 0, utilized: 0, margin: 0 }
    end

    def cancel_order(order_id)
      { success: true, order_id: order_id, status: :canceled, paper: true }
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] cancel_order failed for #{order_id}: #{e.class} - #{e.message}")
      { success: false, order_id: order_id, status: :failed, error: e.message, paper: true }
    end

    # Returns unified shape: { qty:, avg_price:, upnl:, rpnl:, last_ltp:, product_type:, exchange_segment:, position_type:, trading_symbol:, status: }
    def position(segment:, security_id:)
      tracker = PositionTracker.paper.active.find_by(segment: segment, security_id: security_id.to_s)
      return nil unless tracker

      is_long = tracker.side.to_s.upcase.start_with?('LONG') || tracker.side.to_s.upcase == 'BUY'
      position_type = is_long ? 'LONG' : 'SHORT'
      ltp = Live::TickQuery.for_security(segment: segment, security_id: security_id.to_s)&.ltp
      upnl = BigDecimal((tracker.current_pnl_rupees || 0).to_s)

      {
        qty: tracker.quantity,
        avg_price: tracker.avg_price.to_f,
        upnl: upnl,
        rpnl: BigDecimal(0),
        last_ltp: ltp ? BigDecimal(ltp.to_s) : BigDecimal((tracker.avg_price || 0).to_s),
        product_type: nil,
        exchange_segment: tracker.segment,
        position_type: position_type,
        trading_symbol: tracker.symbol,
        status: tracker.status
      }
    end
  end
end
