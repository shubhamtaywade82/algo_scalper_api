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

    def place_ioc_limit(side:, segment:, security_id:, qty:, price:, meta: {})
      # Paper mode: IOC always fills at the given price
      {
        success: true,
        order_id: "PAPER-IOC-#{SecureRandom.hex(3)}",
        paper: true,
        status: :accepted,
        fill_price: price.to_f
      }
    rescue StandardError => e
      Rails.logger.error("[GatewayPaper] place_ioc_limit failed for #{segment}-#{security_id}: #{e.class} - #{e.message}")
      { success: false, error: e.message, paper: true }
    end

    # Returns unified shape: { cash:, equity:, mtm:, exposure:, utilized:, margin: }
    # cash = free balance (like broker available); utilized/exposure = premium tied in open legs.
    def wallet_snapshot
      if ledger_wallet_enabled?
        ledger = Ledger::WalletReader.snapshot(mode: :paper)
        return ledger if ledger[:utilized] >= 0

        Rails.logger.warn("[GatewayPaper] ledger wallet state invalid (utilized=#{ledger[:utilized]}), falling back to legacy")
      end

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

      { cash: cash, equity: equity, mtm: mtm, exposure: exposure, utilized: utilized, margin: 0, source: "legacy" }
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

      is_long = tracker.side.to_s.upcase.start_with?("LONG") || tracker.side.to_s.upcase == "BUY"
      position_type = is_long ? "LONG" : "SHORT"
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

    private

    def paper_trading_config
      AlgoConfig.fetch[:paper_trading] || {}
    end

    def paper_realized_rupees(cfg)
      scope = cfg[:realized_scope].to_s.strip.downcase
      rel = PositionTracker.exited_paper
      rel = rel.where(exited_at: Time.zone.today.all_day) if scope == "daily"

      rel.sum(:last_pnl_rupees).to_f
    end

    def deployed_premium_rupees
      sql = "ABS(COALESCE(entry_price, 0) * COALESCE(quantity, 0))"
      PositionTracker.paper.active.sum(Arel.sql(sql)).to_f
    end

    def active_unrealized_rupees
      PositionTracker.paper.active.sum { |t| t.current_pnl_rupees.to_f }
    end

    def ledger_wallet_enabled?
      Ledger::Config.paper_enabled?
    end
  end
end
