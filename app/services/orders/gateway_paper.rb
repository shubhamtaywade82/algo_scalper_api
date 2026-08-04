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

      tick = Live::TickQuery.for_security(segment: segment, security_id: security_id.to_s)
      fill_price = if tick&.bid.to_f.positive? && tick&.ask.to_f.positive?
                     side.to_s.downcase == 'buy' ? tick.ask.to_f : tick.bid.to_f
                   else
                     (meta[:ltp] || meta[:price] || 0).to_f
                   end

      {
        success: true,
        order_id: order_no,
        paper: true,
        status: :accepted,
        fill_price: fill_price
      }
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] place_market failed for #{segment}-#{security_id}: #{e.class} - #{e.message}")
      { success: false, error: e.message, paper: true }
    end

    def wallet_snapshot
      base = (AlgoConfig.fetch.dig(:paper_trading, :balance) || 100_000).to_f

      # Realized P&L: today's closed paper positions only (daily paper session)
      today = Time.zone.today
      realized = PositionTracker.paper.exited
                                .where(exited_at: today.all_day)
                                .sum(:last_pnl_rupees).to_f

      # Unrealized P&L: active positions read from Redis cache for live values
      unrealized = PositionTracker.paper.active.sum { |t| t.current_pnl_rupees.to_f }

        Rails.logger.warn("[GatewayPaper] ledger wallet state invalid (utilized=#{ledger[:utilized]}), falling back to legacy")
      end

      legacy_wallet_snapshot
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] wallet_snapshot failed: #{e.class} - #{e.message}")
      { cash: 100_000, equity: 100_000, mtm: 0, exposure: 0 } # Return default on error
    end

    def cancel_order(order_id)
      { success: true, order_id: order_id, status: :canceled, paper: true }
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] cancel_order failed for #{order_id}: #{e.class} - #{e.message}")
      { success: false, order_id: order_id, status: :failed, error: e.message, paper: true }
    end

    # Paper position by segment/security_id. Returns same shape as GatewayLive#position for compatibility.
    def position(segment:, security_id:)
      tracker = PositionTracker.paper.active.find_by(segment: segment, security_id: security_id.to_s)
      return nil unless tracker

      position_type = (tracker.side.to_s.upcase.start_with?('LONG') || tracker.side.to_s.upcase == 'BUY') ? 'LONG' : 'SHORT'
      {
        qty: tracker.quantity,
        avg_price: tracker.avg_price.to_f,
        product_type: nil,
        exchange_segment: tracker.segment,
        position_type: position_type,
        trading_symbol: tracker.symbol,
        status: tracker.status
      }
    end
  end
end
