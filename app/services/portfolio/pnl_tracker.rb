# frozen_string_literal: true

module Portfolio
  # Redis-backed real-time portfolio PnL tracker.
  #
  # Maintains per-position unrealized PnL (updated every :ltp tick event)
  # and cumulative realized PnL (updated on exit). Exposes net PnL across
  # all positions as the single source of truth for ProfitLockEngine.
  #
  # All Redis keys are day-scoped and expire after 26 hours.
  class PnlTracker
    REDIS_URL      = ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')
    KEY_REALIZED   = 'portfolio:pnl:realized'
    KEY_REALIZED_TRACKERS = 'portfolio:pnl:realized_trackers'
    KEY_UNREALIZED = 'portfolio:pnl:unrealized'
    KEY_PEAK       = 'portfolio:pnl:peak'
    KEY_FLOOR      = 'portfolio:pnl:floor'
    KEY_LEVEL      = 'portfolio:pnl:level'
    TTL            = 26.hours.to_i

    class << self
      # Update unrealized PnL for a single position.
      # Called on every :ltp EventBus event (high-frequency path).
      #
      # @param tracker_id [Integer]
      # @param pnl [Float] current unrealized PnL for this position in ₹
      def update_unrealized(tracker_id:, pnl:)
        return unless enabled?

        r = redis
        return unless r

        r.hset(KEY_UNREALIZED, unrealized_key(tracker_id), pnl.to_f.to_s)
        r.expire(KEY_UNREALIZED, TTL)
      rescue StandardError => e
        log_error('update_unrealized', e)
      end

      # Record realized PnL when a position exits. Idempotent — will not add twice
      # for the same tracker_id on the same day.
      #
      # @param tracker_id [Integer]
      # @param pnl [Float] realized PnL in ₹ (can be negative)
      def mark_realized(tracker_id:, pnl:)
        return unless enabled?

        r = redis
        unless r
          Rails.logger.error("[Portfolio::PnlTracker] mark_realized: Redis client not available")
          return
        end

        # Idempotency check: only add to realized total once per tracker per session.
        # Redis SADD returns 1 if element added, 0 if already present.
        # In Ruby, 0 is truthy, so we must check specifically for 1.
        added = r.sadd(KEY_REALIZED_TRACKERS, tracker_id.to_s)
        if added != 1 && added != true
          Rails.logger.debug("[Portfolio::PnlTracker] Skip mark_realized: tracker=#{tracker_id} already counted today (added=#{added.inspect})")
          return
        end
        r.expire(KEY_REALIZED_TRACKERS, TTL)

        new_total = r.incrbyfloat(KEY_REALIZED, pnl.to_f)
        r.expire(KEY_REALIZED, TTL)

        # Remove from unrealized — position is now closed
        r.hdel(KEY_UNREALIZED, unrealized_key(tracker_id))

        Rails.logger.info(
          "[Portfolio::PnlTracker] Realized tracker=#{tracker_id}: " \
          "₹#{pnl.round(2)} | Total realized: ₹#{new_total.to_f.round(2)}"
        )
      rescue StandardError => e
        log_error('mark_realized', e)
      end

      # Aggregate net PnL = realized + sum of all unrealized entries.
      #
      # @return [Float] net portfolio PnL in ₹
      def net_pnl
        r = redis
        return 0.0 unless r

        realized    = r.get(KEY_REALIZED).to_f
        unrealized  = r.hgetall(KEY_UNREALIZED).values.sum(&:to_f)
        realized + unrealized
      rescue StandardError => e
        log_error('net_pnl', e)
        0.0
      end

      # Highest net PnL reached today (monotonically increasing).
      # @return [Float]
      def peak_pnl
        redis&.get(KEY_PEAK).to_f
      rescue StandardError
        0.0
      end

      # Currently locked profit floor in ₹ (0.0 if unarmed).
      # @return [Float]
      def locked_floor
        redis&.get(KEY_FLOOR).to_f
      rescue StandardError
        0.0
      end

      # Current arm level (0 = unarmed, 1–3 = armed at milestone N).
      # @return [Integer]
      def current_level
        redis&.get(KEY_LEVEL).to_i
      rescue StandardError
        0
      end

      # Ratchet the peak, floor, and level upward.
      # Called by ProfitLockEngine — only moves values UP, never down.
      #
      # @param new_peak  [Float]
      # @param new_floor [Float]
      # @param new_level [Integer]
      def update_lock(new_peak:, new_floor:, new_level:)
        r = redis
        return unless r

        current_peak  = r.get(KEY_PEAK).to_f
        current_floor = r.get(KEY_FLOOR).to_f
        current_lvl   = r.get(KEY_LEVEL).to_i

        if new_peak > current_peak
          r.set(KEY_PEAK, new_peak.round(2).to_s)
          r.expire(KEY_PEAK, TTL)
        end

        if new_floor > current_floor
          r.set(KEY_FLOOR, new_floor.round(2).to_s)
          r.expire(KEY_FLOOR, TTL)
          Rails.logger.info(
            "[Portfolio::PnlTracker] Floor ratcheted: " \
            "₹#{current_floor.round(2)} → ₹#{new_floor.round(2)}"
          )
        end

        if new_level > current_lvl
          r.set(KEY_LEVEL, new_level.to_s)
          r.expire(KEY_LEVEL, TTL)
          Rails.logger.info("[Portfolio::PnlTracker] Arm level: #{current_lvl} → #{new_level}")
        end
      rescue StandardError => e
        log_error('update_lock', e)
      end

      # Reset all portfolio PnL state for the new trading day.
      # Called at market open by the trading daemon bootstrap.
      def reset_day!
        r = redis
        return unless r

        [KEY_REALIZED, KEY_REALIZED_TRACKERS, KEY_UNREALIZED, KEY_PEAK, KEY_FLOOR, KEY_LEVEL].each { |k| r.del(k) }
        Rails.logger.info('[Portfolio::PnlTracker] Daily state reset')
      rescue StandardError => e
        log_error('reset_day!', e)
      end

      # Full state snapshot for dashboards / debugging.
      # @return [Hash]
      def snapshot
        {
          net_pnl: net_pnl.round(2),
          realized_pnl: realized_pnl.round(2),
          unrealized_pnl: unrealized_pnl_sum.round(2),
          peak_pnl: peak_pnl.round(2),
          locked_floor: locked_floor.round(2),
          level: current_level,
          armed: current_level.positive?
        }
      end

      private

      def enabled?
        AlgoConfig.fetch.dig(:profit_lock, :enabled) != false
      rescue StandardError
        true
      end

      def redis
        @redis ||= begin
          r = Redis.new(url: REDIS_URL)
          Rails.logger.info("[Portfolio::PnlTracker] Initialized Redis client for process #{Process.pid}")
          r
        end
      rescue StandardError => e
        Rails.logger.error("[Portfolio::PnlTracker] Redis init error: #{e.message}")
        nil
      end

      def realized_pnl
        redis&.get(KEY_REALIZED).to_f
      rescue StandardError
        0.0
      end

      def unrealized_pnl_sum
        redis&.hgetall(KEY_UNREALIZED)&.values&.sum(&:to_f).to_f
      rescue StandardError
        0.0
      end

      def unrealized_key(tracker_id)
        "t#{tracker_id}"
      end

      def log_error(ctx, err)
        Rails.logger.error("[Portfolio::PnlTracker] #{ctx} error: #{err.class} - #{err.message}")
      end
    end
  end
end
