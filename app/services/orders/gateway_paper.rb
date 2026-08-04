# frozen_string_literal: true

module Orders
  class GatewayPaper < Orders::Gateway
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

    # Returns unified shape: { cash:, equity:, mtm:, exposure:, utilized:, margin: }
    # cash = free balance (like broker available); utilized/exposure = premium tied in open legs.
    def wallet_snapshot
      return Ledger::WalletReader.snapshot(mode: :paper) if ledger_wallet_enabled?

      legacy_wallet_snapshot
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] wallet_snapshot failed: #{e.class} - #{e.message}")
      { cash: 100_000, equity: 100_000, mtm: 0, exposure: 0, utilized: 0, margin: 0 }
    end

    def legacy_wallet_snapshot
      cfg = paper_trading_config
      base = (cfg[:balance] || 100_000).to_f
      realized = paper_realized_rupees(cfg)
      deployed = deployed_premium_rupees
      unrealized = active_unrealized_rupees

      cash_raw = base + realized - deployed
      cash = [cash_raw, 0.0].max.round(2)
      mtm = unrealized.round(2)
      utilized = deployed.round(2)
      exposure = utilized
      equity = (cash + utilized + mtm).round(2)

      { cash: cash, equity: equity, mtm: mtm, exposure: exposure, utilized: utilized, margin: 0, source: 'legacy' }
    end

    def cancel_order(order_id)
      { success: true, order_id: order_id, status: :canceled, paper: true }
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] cancel_order failed for #{order_id}: #{e.class} - #{e.message}")
      { success: false, order_id: order_id, status: :failed, error: e.message, paper: true }
    end

    # Returns unified shape: { qty:, avg_price:, upnl:, rpnl:, last_ltp:, product_type:, exchange_segment:, position_type:, trading_symbol:, status: }
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

    def ledger_wallet_enabled?
      Ledger::Config.paper_enabled?
    end
  end
end
