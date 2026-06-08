# frozen_string_literal: true

module Risk
  class LimitsGuard
    REDIS_URL = ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')
    TTL = 24.hours.to_i

    # Keys (scoped to date)
    def self.key_prefix
      "risk:limits:#{Time.zone.today}"
    end

    def self.trades_count_key
      "#{key_prefix}:trades_count"
    end

    def self.consecutive_losses_key
      "#{key_prefix}:consecutive_losses"
    end

    class << self
      def check_all!
        limits = AlgoConfig.fetch[:risk_limits] || {}
        
        # 1. Max trades per day
        if max_trades_reached?(limits[:daily_max_trades] || 10)
          return { blocked: 'daily_max_trades_reached' }
        end

        # 2. Max open positions
        if max_open_positions_reached?(limits[:max_open_positions] || 3)
          return { blocked: 'max_open_positions_reached' }
        end

        # 3. Consecutive losses
        if consecutive_losses_breached?(limits[:max_consecutive_losses] || 3)
          return { blocked: 'max_consecutive_losses_breached' }
        end

        { blocked: false }
      end

      def record_trade!
        redis&.incr(trades_count_key)
        redis&.expire(trades_count_key, TTL)
      end

      def record_win!
        redis&.set(consecutive_losses_key, 0)
        redis&.expire(consecutive_losses_key, TTL)
      end

      def record_loss!
        redis&.incr(consecutive_losses_key)
        redis&.expire(consecutive_losses_key, TTL)
      end

      def current_stats
        {
          trades_count: redis&.get(trades_count_key).to_i,
          consecutive_losses: redis&.get(consecutive_losses_key).to_i,
          active_positions: PositionTracker.active.count
        }
      end

      private

      def redis
        @redis ||= Redis.new(url: REDIS_URL)
      rescue StandardError => e
        Rails.logger.error "[Risk::LimitsGuard] Redis error: #{e.message}"
        nil
      end

      def max_trades_reached?(limit)
        (redis&.get(trades_count_key).to_i) >= limit
      end

      def max_open_positions_reached?(limit)
        PositionTracker.active.count >= limit
      end

      def consecutive_losses_breached?(limit)
        (redis&.get(consecutive_losses_key).to_i) >= limit
      end
    end
  end
end
