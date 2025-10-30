# frozen_string_literal: true

require 'bigdecimal'
require 'json'

module Paper
  # Redis-based paper trading gateway that simulates order placement
  # Uses TickCache for LTP and applies slippage/fees
  class Gateway < Orders::Gateway
    REDIS_KEY_PREFIX = 'paper:'
    WALLET_KEY = "#{REDIS_KEY_PREFIX}wallet"
    POSITION_KEY_PREFIX = "#{REDIS_KEY_PREFIX}pos:"
    POSITION_INDEX_KEY = "#{REDIS_KEY_PREFIX}pos:index"
    ORDER_LOG_KEY = "#{REDIS_KEY_PREFIX}orders"
    MAX_ORDER_LOGS = 1000

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

      # Only initialize wallet if it doesn't exist
      # If it exists, keep current state (positions might have been synced)
      initialize_wallet unless wallet_exists?
    rescue StandardError => e
      Rails.logger.error("Failed to initialize Paper::Gateway Redis: #{e.message}")
      @redis = nil
    end

    def place_market(side:, segment:, security_id:, qty:, meta: {})
      # Try TickCache first (from WebSocket feed)
      ltp = TickCache.instance.ltp(segment, security_id.to_s)

      # Try LTP from meta if provided (from signal generation)
      unless ltp
        ltp = meta[:ltp] || meta['ltp']
        Rails.logger.debug { "[Paper::Gateway] Using LTP from meta: #{ltp}" } if ltp
      end

      # Fallback: use throttled LTP fetcher if not in cache (respects 30s interval)
      unless ltp
        Rails.logger.warn("[Paper::Gateway] No LTP in TickCache for #{segment}:#{security_id}, using throttled API fetcher")
        ltp = Paper::LtpFetcher.instance.fetch_ltp(segment: segment, security_id: security_id.to_s)
      end

      unless ltp
        Rails.logger.error("[Paper::Gateway] No LTP available for #{segment}:#{security_id} (check WebSocket connection or wait 30s for API throttle)")
        return nil
      end

      ltp_decimal = BigDecimal(ltp.to_s)
      fill_price = apply_slippage(ltp_decimal, side)
      fees = calculate_fees(fill_price, qty)
      total_cost = (fill_price * qty) + fees

      # For SELL, we need to check if we have a position first
      if side.to_s.downcase == 'sell'
        current_pos = fetch_position(segment, security_id.to_s)
        unless current_pos && (current_pos[:qty].to_i > 0)
          Rails.logger.error("[Paper::Gateway] Cannot sell: no position for #{segment}:#{security_id}")
          return nil
        end
      end

      # Read current state before transaction
      wallet_data = @redis.hgetall(WALLET_KEY)
      pos_key = position_key(segment, security_id.to_s)
      position_data = @redis.hgetall(pos_key)

      # Atomic update: wallet + position
      @redis.multi do |m|
        if side.to_s.downcase == 'buy'
          execute_buy(m, segment, security_id.to_s, qty, fill_price, fees, total_cost, meta,
                      wallet_data, position_data)
        else
          execute_sell(m, segment, security_id.to_s, qty, fill_price, fees, meta,
                       wallet_data, position_data)
        end
      end

      # Log order
      log_order(segment: segment, security_id: security_id.to_s, side: side, qty: qty,
                fill_price: fill_price, fees: fees, meta: meta)

      # Return mock order response
      build_order_response(status: 'filled', price: fill_price, quantity: qty,
                           security_id: security_id.to_s, transaction_type: side.upcase)
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] place_market failed: #{e.class} - #{e.message}")
      nil
    end

    def flat_position(segment:, security_id:)
      pos = fetch_position(segment, security_id.to_s)
      return nil unless pos && pos[:qty].to_i != 0

      qty = pos[:qty].to_i.abs
      side = pos[:qty].to_i > 0 ? 'sell' : 'buy' # Opposite direction to flatten

      place_market(side: side, segment: segment, security_id: security_id, qty: qty,
                   meta: { reason: 'flat_position' })
    end

    def position(segment:, security_id:)
      fetch_position(segment, security_id.to_s)
    end

    def wallet_snapshot
      return default_wallet unless @redis

      data = @redis.hgetall(WALLET_KEY)
      return default_wallet if data.empty?

      {
        cash: BigDecimal(data['cash'] || '0'),
        equity: BigDecimal(data['equity'] || '0'),
        mtm: BigDecimal(data['mtm'] || '0'),
        exposure: BigDecimal(data['exposure'] || '0')
      }
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] wallet_snapshot failed: #{e.message}")
      default_wallet
    end

    def on_tick(segment:, security_id:, ltp:)
      return unless @redis

      pos_key = position_key(segment, security_id.to_s)
      pos_data = @redis.hgetall(pos_key)
      return if pos_data.empty? || pos_data['qty'].to_i == 0 # Skip if no position

      # Update position's last_ltp and upnl
      avg_price = BigDecimal(pos_data['avg_price'] || '0')
      qty = pos_data['qty'].to_i
      last_ltp = BigDecimal(ltp.to_s)
      upnl = (last_ltp - avg_price) * qty

      # Update position fields while preserving segment and security_id
      existing_seg = pos_data['segment'] || segment.to_s
      existing_sid = pos_data['security_id'] || security_id.to_s
      @redis.hset(pos_key, 'last_ltp', last_ltp.to_s, 'upnl', upnl.to_s, 'updated_at', Time.current.to_i,
                  'segment', existing_seg, 'security_id', existing_sid)

      # Recompute wallet MTM (throttled - we'll do it every tick but it's fast with index)
      recompute_wallet_mtm
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] on_tick failed for #{segment}:#{security_id}: #{e.message}")
    end

    private

    def execute_buy(multi, segment, security_id, qty, fill_price, _fees, total_cost, _meta,
                    wallet_data, position_data)
      pos_key = position_key(segment, security_id)

      cash = BigDecimal(wallet_data['cash'] || '0')
      raise InsufficientFundsError, "Insufficient cash: #{cash} < #{total_cost}" if cash < total_cost

      # Update wallet
      new_cash = cash - total_cost
      multi.hset(WALLET_KEY, 'cash', new_cash.to_s)

      # Update position
      existing_qty = position_data['qty'].to_i
      existing_avg = BigDecimal(position_data['avg_price'] || '0')

      if existing_qty == 0
        new_avg = fill_price
        new_qty = qty
        rpnl = BigDecimal(0)
      else
        # Average price calculation for adding to existing position
        total_qty = existing_qty + qty
        total_value = (existing_avg * existing_qty) + (fill_price * qty)
        new_avg = total_qty.zero? ? fill_price : (total_value / BigDecimal(total_qty.to_s))
        new_qty = total_qty
        rpnl = BigDecimal(position_data['rpnl'] || '0') # Keep existing realized PnL
      end

      upnl = (fill_price - new_avg) * new_qty # Will be 0 for new buys

      multi.hset(pos_key, {
                   'segment' => segment.to_s,
                   'security_id' => security_id.to_s,
                   'qty' => new_qty.to_s,
                   'avg_price' => new_avg.to_s,
                   'rpnl' => rpnl.to_s,
                   'upnl' => upnl.to_s,
                   'last_ltp' => fill_price.to_s,
                   'updated_at' => Time.current.to_i
                 })

      # Maintain position index
      multi.sadd(POSITION_INDEX_KEY, pos_key) if new_qty != 0
    end

    def execute_sell(multi, segment, security_id, qty, fill_price, fees, _meta,
                     wallet_data, position_data)
      pos_key = position_key(segment, security_id)

      existing_qty = position_data['qty'].to_i
      avg_price = BigDecimal(position_data['avg_price'] || '0')

      raise InsufficientPositionError, "Cannot sell #{qty}, only have #{existing_qty}" if existing_qty < qty

      # Calculate realized PnL for the sold quantity
      realized_pnl = (((fill_price - avg_price) * BigDecimal(qty.to_s)) - fees)
      existing_rpnl = BigDecimal(position_data['rpnl'] || '0')
      new_rpnl = existing_rpnl + realized_pnl

      # Update position
      new_qty = existing_qty - qty
      proceeds = (fill_price * qty) - fees
      current_avg = avg_price # Avg price stays the same for partial sells
      upnl = new_qty == 0 ? BigDecimal(0) : (fill_price - current_avg) * new_qty

      multi.hset(pos_key, {
                   'segment' => segment.to_s,
                   'security_id' => security_id.to_s,
                   'qty' => new_qty.to_s,
                   'avg_price' => current_avg.to_s, # Keep original avg price
                   'rpnl' => new_rpnl.to_s,
                   'upnl' => upnl.to_s,
                   'last_ltp' => fill_price.to_s,
                   'updated_at' => Time.current.to_i
                 })

      # Remove from index if position is flat
      multi.srem(POSITION_INDEX_KEY, pos_key) if new_qty == 0

      # Update wallet
      cash = BigDecimal(wallet_data['cash'] || '0')
      new_cash = cash + proceeds
      multi.hset(WALLET_KEY, 'cash', new_cash.to_s)
    end

    def fetch_position(segment, security_id)
      return nil unless @redis

      pos_key = position_key(segment, security_id)
      data = @redis.hgetall(pos_key)
      return nil if data.empty? || data['qty'].to_i == 0

      {
        segment: segment,
        security_id: security_id.to_s,
        qty: data['qty'].to_i,
        avg_price: BigDecimal(data['avg_price'] || '0'),
        upnl: BigDecimal(data['upnl'] || '0'),
        rpnl: BigDecimal(data['rpnl'] || '0'),
        last_ltp: BigDecimal(data['last_ltp'] || data['avg_price'] || '0'),
        updated_at: data['updated_at']&.to_i
      }
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] fetch_position failed: #{e.message}")
      nil
    end

    def recompute_wallet_mtm
      return unless @redis

      # Get all active positions from index
      pos_keys = @redis.smembers(POSITION_INDEX_KEY)
      return if pos_keys.empty?

      total_mtm = BigDecimal(0)
      total_exposure = BigDecimal(0)

      pos_keys.each do |pos_key|
        pos_data = @redis.hgetall(pos_key)
        next if pos_data.empty?

        qty = pos_data['qty'].to_i
        next if qty == 0

        avg_price = BigDecimal(pos_data['avg_price'] || '0')
        last_ltp = BigDecimal(pos_data['last_ltp'] || avg_price.to_s)
        upnl = (last_ltp - avg_price) * qty

        total_mtm += upnl
        total_exposure += last_ltp.abs * qty.abs
      end

      cash = BigDecimal(@redis.hget(WALLET_KEY, 'cash') || '0')
      equity = cash + total_mtm

      @redis.hset(WALLET_KEY, {
                    'mtm' => total_mtm.to_s,
                    'equity' => equity.to_s,
                    'exposure' => total_exposure.to_s
                  })
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] recompute_wallet_mtm failed: #{e.message}")
    end

    # Write position directly to Redis (used for syncing from PositionTracker)
    # @private - used by Paper::PositionSync
    def write_position_to_redis(segment, security_id, position_data)
      return unless @redis

      pos_key = position_key(segment, security_id)

      @redis.hset(pos_key, {
                    'segment' => segment.to_s,
                    'security_id' => security_id.to_s,
                    'qty' => position_data[:qty].to_s,
                    'avg_price' => position_data[:avg_price].to_s,
                    'rpnl' => position_data[:rpnl].to_s,
                    'upnl' => position_data[:upnl].to_s,
                    'last_ltp' => position_data[:last_ltp].to_s,
                    'updated_at' => Time.current.to_i # Store timestamp for freshness check
                  })

      # Add to position index if qty != 0
      return unless position_data[:qty].to_i != 0

      @redis.sadd(POSITION_INDEX_KEY, pos_key)
    end

    # Check if position data in Redis is fresh (< 6 hours old)
    # Used by PositionSync to determine if sync is needed
    def position_fresh?(segment, security_id, max_age_hours: 6)
      return false unless @redis

      pos_key = position_key(segment, security_id)
      data = @redis.hgetall(pos_key)
      return false if data.empty?

      updated_at = data['updated_at']&.to_i
      return false unless updated_at

      age_hours = (Time.current.to_i - updated_at) / 3600.0
      age_hours < max_age_hours
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] position_fresh? failed: #{e.message}")
      false
    end

    def apply_slippage(ltp, side)
      slippage_bps = BigDecimal(ENV.fetch('PAPER_SLIPPAGE_BPS', '2'))
      slippage_pct = slippage_bps / 10_000

      case side.to_s.downcase
      when 'buy'
        ltp * (BigDecimal(1) + slippage_pct) # Pay more
      when 'sell'
        ltp * (BigDecimal(1) - slippage_pct) # Receive less
      else
        ltp
      end
    end

    def calculate_fees(price, qty)
      fees_bps = BigDecimal(ENV.fetch('PAPER_FEES_BPS', '5'))
      fees_pct = fees_bps / 10_000
      (price * qty) * fees_pct
    end

    def position_key(segment, security_id)
      "#{POSITION_KEY_PREFIX}#{segment}:#{security_id}"
    end

    def wallet_exists?
      return false unless @redis

      @redis.exists?(WALLET_KEY)
    end

    def initialize_wallet
      return unless @redis

      seed_cash = BigDecimal(ENV.fetch('PAPER_SEED_CASH', '100000'))
      @redis.hset(WALLET_KEY, {
                    'cash' => seed_cash.to_s,
                    'mtm' => '0',
                    'equity' => seed_cash.to_s,
                    'exposure' => '0'
                  })
      Rails.logger.info("[Paper::Gateway] Initialized wallet with #{seed_cash} cash")
    end

    def default_wallet
      {
        cash: BigDecimal(0),
        equity: BigDecimal(0),
        mtm: BigDecimal(0),
        exposure: BigDecimal(0)
      }
    end

    def log_order(segment:, security_id:, side:, qty:, fill_price:, fees:, meta:)
      return unless @redis

      order_log = {
        timestamp: Time.current.to_i,
        segment: segment,
        security_id: security_id,
        side: side,
        qty: qty,
        fill_price: fill_price.to_f,
        fees: fees.to_f,
        meta: meta
      }.to_json

      @redis.lpush(ORDER_LOG_KEY, order_log)
      @redis.ltrim(ORDER_LOG_KEY, 0, MAX_ORDER_LOGS - 1)
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] log_order failed: #{e.message}")
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

    # Return recent order logs from Redis (most recent first)
    def order_logs(limit: 100)
      return [] unless @redis

      safe_limit = limit.to_i.positive? ? [limit.to_i, MAX_ORDER_LOGS].min : 100
      @redis.lrange(ORDER_LOG_KEY, 0, safe_limit - 1).map do |row|
        JSON.parse(row, symbolize_names: true)
      end
    rescue StandardError => e
      Rails.logger.error("[Paper::Gateway] order_logs failed: #{e.message}")
      []
    end

    class InsufficientFundsError < StandardError; end
    class InsufficientPositionError < StandardError; end
  end
end
