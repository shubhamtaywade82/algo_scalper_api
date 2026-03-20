# frozen_string_literal: true

module Portfolio
  class DrawdownGuard
    REDIS_BLOCK_KEY = "trading:profit_protection_blocked"

    class << self
      def trigger_global_exit!(total_pnl: 0, floor: 0)
        # 1. Fetch all active positions from ActiveCache
        active_positions = Positions::ActiveCache.instance.all_positions
        
        if active_positions.empty?
          Rails.logger.info("[DrawdownGuard] No active positions to exit.")
        else
          Rails.logger.warn("[DrawdownGuard] Exiting #{active_positions.size} positions to protect profits (PnL: ₹#{total_pnl} <= Floor: ₹#{floor})")
          
          active_positions.each do |pos_data|
            tracker = PositionTracker.find_by(id: pos_data.tracker_id)
            next unless tracker&.active?
            
            Orders::Executor.exit_market!(tracker: tracker, reason: 'profit_protection_breach')
          end
        end

        # 2. Block new entries for the rest of the day
        block_new_entries!
        
        # 3. Notify
        notify_breach(total_pnl, floor)
      end

      def block_new_entries!
        # Set a block key in Redis that expires at the end of the day (15:30 IST)
        expiry_seconds = TradingSession::Service.seconds_until_session_end
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')).setex(REDIS_BLOCK_KEY, [expiry_seconds, 60].max, "true")
        Rails.logger.info("[DrawdownGuard] New entries blocked until end of session.")
      end

      def blocked?
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')).get(REDIS_BLOCK_KEY) == "true"
      rescue StandardError => e
        Rails.logger.error("[DrawdownGuard] Error checking block status: #{e.message}")
        false
      end

      def unblock!
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')).del(REDIS_BLOCK_KEY)
        Rails.logger.info("[DrawdownGuard] Manual unblock successful.")
      end

      private

      def notify_breach(pnl, floor)
        # Check if TelegramNotifier is available
        return unless defined?(::TelegramNotifier)
        
        msg = "🚨 *Profit Protection Triggered*\n" \
              "Current PnL: ₹#{pnl.round(2)}\n" \
              "Breached Floor: ₹#{floor.round(2)}\n" \
              "Actions: All positions exited & new entries blocked."
        
        ::TelegramNotifier.send_message(msg) rescue nil
      end
    end
  end
end
