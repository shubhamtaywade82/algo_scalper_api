# frozen_string_literal: true

module Orders
  class GatewayPaper < Orders::Gateway
    def exit_market(tracker, client_order_id: nil)
      tick = Live::TickQuery.for_security(segment: tracker.segment, security_id: tracker.security_id)
      # For long exits (selling), use bid; for short exits (buying to cover), use ask
      exit_price = resolve_exit_fill(tracker, tick)
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
      tick = resolve_fresh_tick(segment: segment, security_id: security_id.to_s)
      fill_price = resolve_entry_fill(side, tick, nil)

      # Simulate broker ack only; domain services own tracker persistence.
      { success: true, order_id: order_no, paper: true, fill_price: fill_price&.to_f }
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

    def modify_order(order_id, params = {})
      { success: true, order_id: order_id, status: :modified, paper: true, params: params }
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

    private

    def resolve_fresh_tick(segment:, security_id:)
      tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
      return tick if tick&.ltp&.positive? && tick_fresh?(tick)

      fetch_api_tick(segment: segment, security_id: security_id) || tick
    end

    def tick_fresh?(tick)
      return true unless tick.respond_to?(:timestamp) && tick.timestamp

      (Time.current - tick.timestamp).abs <= 5.seconds
    end

    def fetch_api_tick(segment:, security_id:)
      return nil unless defined?(DhanHQ::Models::MarketFeed)

      segment_enum = segment.to_s.upcase
      payload = { segment_enum => [security_id.to_i] }
      response = DhanHQ::Models::MarketFeed.ltp(payload)
      return nil unless response.is_a?(Hash) && response['status'] == 'success'

      data = response.dig('data', segment_enum, security_id.to_s)
      price = data&.dig('last_price')
      return nil unless price&.to_f&.positive?

      MarketTick.new(
        segment: segment,
        security_id: security_id,
        ltp: BigDecimal(price.to_s),
        timestamp: Time.current,
        oi: 0,
        oi_change: 0,
        bid: price.to_f,
        ask: price.to_f,
        volume: 0,
        prev_close: price.to_f
      )
    rescue StandardError => e
      Rails.logger.debug { "[GatewayPaper] fetch_api_tick failed for #{segment}:#{security_id}: #{e.message}" }
      nil
    end

    def resolve_exit_fill(tracker, tick)
      is_long = tracker.position_side.to_s.downcase.start_with?('long')
      raw_price = if is_long
                    # Selling: use bid price (worse for seller)
                    tick&.bid || tick&.ltp || tracker.entry_price
                  else
                    # Buying to cover: use ask price (worse for buyer)
                    tick&.ask || tick&.ltp || tracker.entry_price
                  end
      raw_price ||= tracker.entry_price || 100.0
      apply_slippage(BigDecimal(raw_price.to_s), is_long ? :sell : :buy)
    end

    def resolve_entry_fill(side, tick, fallback_ltp)
      raw_price = if side.to_s.upcase == 'BUY'
                    # Buying: use ask price (worse for buyer)
                    tick&.ask || tick&.ltp || fallback_ltp
                  else
                    # Selling: use bid price (worse for seller)
                    tick&.bid || tick&.ltp || fallback_ltp
                  end
      raw_price ||= fallback_ltp || 100.0

      apply_slippage(BigDecimal(raw_price.to_s), side.to_s.upcase.to_sym)
    end

    def apply_slippage(price, side)
      return price unless slippage_enabled?

      tick_size = BigDecimal('0.05') # Default NSE option tick size
      ticks = side == :BUY ? slippage_buy_ticks : slippage_sell_ticks
      adjustment = tick_size * ticks

      side == :BUY ? price + adjustment : price - adjustment
    end

    def slippage_enabled?
      if AlgoConfig.respond_to?(:dig)
        val = AlgoConfig.dig('paper_trading', 'slippage', 'enabled')
        val = AlgoConfig.dig(:paper_trading, :slippage, :enabled) if val.nil?
        return val unless val.nil?
      end

      slippage_cfg[:enabled] == true || slippage_cfg['enabled'] == true
    end

    def slippage_buy_ticks
      if AlgoConfig.respond_to?(:dig)
        val = AlgoConfig.dig('paper_trading', 'slippage', 'market_buy_ticks')
        val = AlgoConfig.dig(:paper_trading, :slippage, :market_buy_ticks) if val.nil?
        return val.to_i if val.present?
      end

      (slippage_cfg[:market_buy_ticks] || slippage_cfg['market_buy_ticks'])&.to_i || 1
    end

    def slippage_sell_ticks
      if AlgoConfig.respond_to?(:dig)
        val = AlgoConfig.dig('paper_trading', 'slippage', 'market_sell_ticks')
        val = AlgoConfig.dig(:paper_trading, :slippage, :market_sell_ticks) if val.nil?
        return val.to_i if val.present?
      end

      (slippage_cfg[:market_sell_ticks] || slippage_cfg['market_sell_ticks'])&.to_i || 1
    end

    def slippage_cfg
      cfg = AlgoConfig.fetch
      cfg[:paper_trading]&.dig(:slippage) || cfg['paper_trading']&.dig('slippage') || {}
    rescue StandardError
      {}
    end
  end
end
