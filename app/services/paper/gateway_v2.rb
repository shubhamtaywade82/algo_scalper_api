# frozen_string_literal: true

require 'bigdecimal'
require 'json'
require 'ostruct'

module Paper
  # Daily-namespaced Redis gateway for paper trading (Phase 2)
  # Does not alter Live systems. Routing switch can be done after validation.
  class GatewayV2 < Orders::Gateway
    BUY_CHARGE = BigDecimal(20)
    SELL_CHARGE = BigDecimal(20)

    MAX_ORDER_LOGS = 1000

    def initialize(redis: Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')))
      @redis = redis
      seed_wallet!
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] Redis init failed: #{e.message}")
      @redis = nil
    end

    # --- Public API ---

    def place_market(side:, segment:, security_id:, qty:, meta: {})
      return nil unless @redis

      ltp = resolve_ltp(segment, security_id, meta)
      unless ltp
        Rails.logger.error("[Paper::GatewayV2] resolve_ltp returned nil for #{segment}:#{security_id}")
        puts "[Paper::GatewayV2] resolve_ltp returned nil for #{segment}:#{security_id}"
        return nil
      end

      ns = Paper::TradingClock.redis_ns
      now = Time.current

      case side.to_s.downcase
      when 'buy'
        premium = (ltp * qty)
        debit = premium + BUY_CHARGE

        @redis.multi do |tx|
          tx.hincrbyfloat(wallet_key(ns), 'cash', -debit.to_f)
          tx.hincrbyfloat(wallet_key(ns), 'fees_total', BUY_CHARGE.to_f)
          # used_amount while open = premium + buy_charge
          tx.hset(wallet_key(ns), 'used_amount', (premium + BUY_CHARGE).to_s)

          upsert_position_buy(tx, ns, segment, security_id, qty, ltp)
          push_order_log(tx, ns, 'buy', segment, security_id, qty, ltp, BUY_CHARGE, now, meta)
        end
        refresh_equity!(nil, ns)

        enqueue_fill(trading_ns: ns, side: 'buy', segment: segment, security_id: security_id,
                     qty: qty, price: ltp, charge: BUY_CHARGE, executed_at: now, meta: meta)

        build_order_response(status: 'filled', price: ltp, quantity: qty, security_id: security_id,
                             transaction_type: 'BUY')
      when 'sell'
        proceeds = (ltp * qty)
        credit = proceeds - SELL_CHARGE

        @redis.multi do |tx|
          tx.hincrbyfloat(wallet_key(ns), 'cash', credit.to_f)
          tx.hincrbyfloat(wallet_key(ns), 'fees_total', SELL_CHARGE.to_f)

          upsert_position_sell(tx, ns, segment, security_id, qty, ltp)
          push_order_log(tx, ns, 'sell', segment, security_id, qty, ltp, SELL_CHARGE, now, meta)
          # Equity recalculation will be done post-tx to see latest state
        end
        # Post-transaction updates that depend on committed state
        refresh_equity!(nil, ns)
        @redis.hset(wallet_key(ns), 'used_amount', cumulative_fees(ns).to_s) if flat?(ns, segment, security_id)
        # If all positions are flat for the day, persist today's wallet snapshot
        persist_daily_wallet_snapshot(ns) unless any_open_positions?(ns)
        enqueue_fill(trading_ns: ns, side: 'sell', segment: segment, security_id: security_id,
                     qty: qty, price: ltp, charge: SELL_CHARGE, executed_at: now, meta: meta)

        build_order_response(status: 'filled', price: ltp, quantity: qty, security_id: security_id,
                             transaction_type: 'SELL')
      else
        Rails.logger.warn("[Paper::GatewayV2] Unsupported side: #{side}")
        nil
      end
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] place_market failed: #{e.class} - #{e.message}")
      puts "[Paper::GatewayV2] place_market failed: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      nil
    end

    def flat_position(segment:, security_id:)
      return nil unless @redis

      ns = Paper::TradingClock.redis_ns
      pos = get_pos(ns, segment, security_id)
      return { status: 'flat' } if pos[:qty].zero?

      side = pos[:qty].positive? ? 'sell' : 'buy'
      place_market(side: side, segment: segment, security_id: security_id, qty: pos[:qty].abs, meta: { action: 'flat' })
    end

    def position(segment:, security_id:)
      return nil unless @redis

      ns = Paper::TradingClock.redis_ns
      pos = get_pos(ns, segment, security_id)
      return nil if pos[:qty].zero?

      {
        segment: segment,
        security_id: security_id.to_s,
        qty: pos[:qty],
        avg_price: BigDecimal(pos[:avg].to_s),
        upnl: BigDecimal(pos[:upnl].to_s),
        rpnl: BigDecimal(pos[:rpnl].to_s),
        last_ltp: pos[:last_ltp] ? BigDecimal(pos[:last_ltp].to_s) : BigDecimal(0)
      }
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] position failed: #{e.message}")
      nil
    end

    def wallet_snapshot
      return default_wallet unless @redis

      ns = Paper::TradingClock.redis_ns
      h = @redis.hgetall(wallet_key(ns))
      return default_wallet if h.empty?

      cash = BigDecimal(h['cash'] || '0')
      realized = BigDecimal(h['realized_pnl'] || '0')
      unrealized = BigDecimal(h['unrealized_pnl'] || '0')
      # Equity (net liquidation) = Cash + Unrealized MTM
      # Realized PnL has already been reflected into cash
      equity = cash + unrealized

      {
        cash: cash,
        used_amount: BigDecimal(h['used_amount'] || '0'),
        equity: equity,
        realized_pnl: realized,
        unrealized_pnl: unrealized,
        fees_total: BigDecimal(h['fees_total'] || '0'),
        max_equity: BigDecimal(h['max_equity'] || equity.to_s),
        min_equity: BigDecimal(h['min_equity'] || equity.to_s)
      }
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] wallet_snapshot failed: #{e.message}")
      default_wallet
    end

    def on_tick(segment:, security_id:, ltp:)
      return unless @redis

      ns = Paper::TradingClock.redis_ns
      k = pos_key(ns, segment, security_id)
      qty = @redis.hget(k, 'qty').to_i
      return if qty.zero?

      avg = BigDecimal(@redis.hget(k, 'avg') || '0')
      last_ltp = BigDecimal(ltp.to_s)
      upnl = (last_ltp - avg) * qty
      @redis.hmset(k, 'upnl', upnl.to_s, 'last_ltp', last_ltp.to_s)

      refresh_equity!(nil, ns)
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] on_tick failed: #{e.message}")
    end

    def order_logs(limit: 100)
      return [] unless @redis

      ns = Paper::TradingClock.redis_ns
      safe_limit = limit.to_i.positive? ? [limit.to_i, MAX_ORDER_LOGS].min : 100
      @redis.lrange(orders_key(ns), 0, safe_limit - 1).map { |row| JSON.parse(row, symbolize_names: true) }
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] order_logs failed: #{e.message}")
      []
    end

    # --- Internals ---
    private

    def wallet_key(ns)
      "#{ns}:wallet"
    end

    def pos_key(ns, seg, sid)
      "#{ns}:pos:#{seg}:#{sid}"
    end

    def pos_index_key(ns)
      "#{ns}:pos:index"
    end

    def orders_key(ns)
      "#{ns}:orders"
    end

    def seed_wallet!
      return unless @redis

      ns = Paper::TradingClock.redis_ns
      seed_cash = BigDecimal(ENV.fetch('PAPER_SEED_CASH', '100000'))
      # Only seed if empty
      return unless @redis.hlen(wallet_key(ns)).zero?

      @redis.hmset(
        wallet_key(ns),
        'cash', seed_cash.to_s,
        'used_amount', '0',
        'equity', seed_cash.to_s,
        'realized_pnl', '0',
        'unrealized_pnl', '0',
        'fees_total', '0',
        'max_equity', seed_cash.to_s,
        'min_equity', seed_cash.to_s
      )
    end

    def default_wallet
      {
        cash: BigDecimal(0),
        used_amount: BigDecimal(0),
        equity: BigDecimal(0),
        realized_pnl: BigDecimal(0),
        unrealized_pnl: BigDecimal(0),
        fees_total: BigDecimal(0),
        max_equity: BigDecimal(0),
        min_equity: BigDecimal(0)
      }
    end

    def resolve_ltp(segment, security_id, meta)
      # Prefer meta ltp → TickCache → nil
      ltp = meta[:ltp] || meta['ltp']
      return BigDecimal(ltp.to_s) if ltp

      cache_ltp = TickCache.instance.ltp(segment, security_id.to_s)
      return BigDecimal(cache_ltp.to_s) if cache_ltp

      nil
    end

    def get_pos(ns, seg, sid)
      h = @redis.hgetall(pos_key(ns, seg, sid))
      return { qty: 0, avg: 0.0, rpnl: 0.0, upnl: 0.0, last_ltp: nil } if h.empty?

      {
        qty: h['qty'].to_i,
        avg: (h['avg'] ? h['avg'].to_f : 0.0),
        rpnl: (h['rpnl'] ? h['rpnl'].to_f : 0.0),
        upnl: (h['upnl'] ? h['upnl'].to_f : 0.0),
        last_ltp: (h['last_ltp'] ? h['last_ltp'].to_f : nil)
      }
    end

    def upsert_position_buy(tx, ns, seg, sid, qty, px)
      k = pos_key(ns, seg, sid)
      cur = get_pos(ns, seg, sid)
      new_qty = cur[:qty] + qty
      new_avg = if cur[:qty] <= 0
                  BigDecimal(px.to_s)
                else
                  (((BigDecimal(cur[:avg].to_s) * cur[:qty]) + (BigDecimal(px.to_s) * qty)) / new_qty)
                end

      tx.hmset(k, 'qty', new_qty.to_s, 'avg', new_avg.to_s, 'rpnl', BigDecimal(cur[:rpnl].to_s).to_s)
      tx.sadd(pos_index_key(ns), k)
    end

    def upsert_position_sell(tx, ns, seg, sid, qty, px)
      k = pos_key(ns, seg, sid)
      cur = get_pos(ns, seg, sid)
      return if cur[:qty].zero?

      sign = cur[:qty] >= 0 ? 1 : -1
      close_qty = [qty, cur[:qty].abs].min
      realized = (BigDecimal(px.to_s) - BigDecimal(cur[:avg].to_s)) * (close_qty * sign)
      new_rpnl = BigDecimal(cur[:rpnl].to_s) + realized
      new_qty = cur[:qty] - (close_qty * sign)
      new_avg = new_qty.zero? ? BigDecimal(0) : BigDecimal(cur[:avg].to_s)

      tx.hmset(k, 'qty', new_qty.to_s, 'avg', new_avg.to_s, 'rpnl', new_rpnl.to_s, 'upnl', '0', 'last_ltp',
               BigDecimal(px.to_s).to_s)
      tx.srem(pos_index_key(ns), k) if new_qty.zero?
      tx.hincrbyfloat(wallet_key(ns), 'realized_pnl', realized.to_f)
    end

    def flat?(ns, seg, sid)
      @redis.hget(pos_key(ns, seg, sid), 'qty').to_i.zero?
    end

    def cumulative_fees(ns)
      BigDecimal(@redis.hget(wallet_key(ns), 'fees_total') || '0')
    end

    def refresh_equity!(tx, ns)
      upnl_sum = BigDecimal(0)
      @redis.smembers(pos_index_key(ns)).each do |k|
        h = @redis.hgetall(k)
        upnl_sum += BigDecimal(h['upnl'] || '0')
      end

      if tx
        tx.hset(wallet_key(ns), 'unrealized_pnl', upnl_sum.to_s)
        # equity = cash + unrealized (realized already in cash); update bounds
        script = <<~LUA
          local w = KEYS[1]
          local c = tonumber(redis.call('HGET', w, 'cash') or '0')
          local u = tonumber(redis.call('HGET', w, 'unrealized_pnl') or '0')
          local e = c + u
          redis.call('HSET', w, 'equity', tostring(e))
          local maxe = tonumber(redis.call('HGET', w, 'max_equity') or tostring(e))
          local mine = tonumber(redis.call('HGET', w, 'min_equity') or tostring(e))
          if e > maxe then redis.call('HSET', w, 'max_equity', tostring(e)) end
          if e < mine then redis.call('HSET', w, 'min_equity', tostring(e)) end
        LUA
        @redis.eval(script, keys: [wallet_key(ns)])
      else
        @redis.hset(wallet_key(ns), 'unrealized_pnl', upnl_sum.to_s)
        cash = BigDecimal(@redis.hget(wallet_key(ns), 'cash') || '0')
        e = cash + upnl_sum
        @redis.hset(wallet_key(ns), 'equity', e.to_s)
        maxe = BigDecimal(@redis.hget(wallet_key(ns), 'max_equity') || e.to_s)
        mine = BigDecimal(@redis.hget(wallet_key(ns), 'min_equity') || e.to_s)
        @redis.hset(wallet_key(ns), 'max_equity', e.to_s) if e > maxe
        @redis.hset(wallet_key(ns), 'min_equity', e.to_s) if e < mine
      end
    end

    def push_order_log(tx, ns, side, seg, sid, qty, px, fee, now, meta)
      payload = { ts: now.to_f, side: side, segment: seg, security_id: sid.to_s, qty: qty, price: px.to_f,
                  fee: fee.to_f, meta: meta }.to_json
      tx.lpush(orders_key(ns), payload)
      tx.ltrim(orders_key(ns), 0, MAX_ORDER_LOGS - 1)
    end

    def build_order_response(status:, price:, quantity:, security_id:, transaction_type:)
      order_no = "PAPER-#{transaction_type}-#{security_id}-#{Time.current.strftime('%Y%m%d%H%M%S')}"
      OpenStruct.new(
        order_id: order_no,
        order_no: order_no,
        order_status: status == 'filled' ? 'COMPLETE' : status.upcase,
        status: status,
        price: price.to_f,
        quantity: quantity,
        security_id: security_id,
        transaction_type: transaction_type
      )
    end

    def enqueue_fill(trading_ns:, side:, segment:, security_id:, qty:, price:, charge:, executed_at:, meta:)
      date = trading_ns.split(':', 2).last
      gross = (BigDecimal(price.to_s) * qty).round(2)
      net = side == 'buy' ? (gross + BigDecimal(charge.to_s)) : (gross - BigDecimal(charge.to_s))

      Paper::PersistFillJob.perform_later(
        trading_date: date,
        exchange_segment: segment,
        security_id: security_id.to_i,
        side: side,
        qty: qty,
        price: price.to_f,
        charge: charge.to_f,
        gross_value: gross.to_f,
        net_value: net.to_f,
        executed_at: executed_at,
        meta: meta || {}
      )
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] enqueue_fill failed: #{e.message}")
    end

    # Returns true if there is at least one open position in the current day's namespace
    def any_open_positions?(ns)
      @redis.scard(pos_index_key(ns)).to_i.positive?
    end

    # Upsert a snapshot of the day's wallet into PaperDailyWallet when all positions are closed
    def persist_daily_wallet_snapshot(ns)
      date_str = ns.split(':', 2).last
      date = Date.parse(date_str)

      w = @redis.hgetall(wallet_key(ns))
      return if w.empty?

      opening = opening_cash_for(date) || w['cash'].to_f
      closing = w['cash'].to_f
      realized = w['realized_pnl'].to_f
      unrealized = w['unrealized_pnl'].to_f
      fees = w['fees_total'].to_f
      equity = w['equity'].to_f
      max_eq = w['max_equity'].to_f
      min_eq = w['min_equity'].to_f
      trades_count = ::PaperFillsLog.where(trading_date: date).count

      ::PaperDailyWallet.upsert(
        {
          trading_date: date,
          opening_cash: opening,
          closing_cash: closing,
          gross_pnl: (realized + unrealized),
          fees_total: fees,
          net_pnl: (realized + unrealized - fees),
          max_drawdown: (max_eq - min_eq).abs,
          max_equity: max_eq,
          min_equity: min_eq,
          trades_count: trades_count,
          meta: { paper_mode: true, equity: equity }
        },
        unique_by: :trading_date
      )
    rescue StandardError => e
      Rails.logger.error("[Paper::GatewayV2] persist_daily_wallet_snapshot failed: #{e.message}")
    end

    def opening_cash_for(date)
      ::PaperDailyWallet.find_by(trading_date: date - 1)&.closing_cash
    end
  end
end
