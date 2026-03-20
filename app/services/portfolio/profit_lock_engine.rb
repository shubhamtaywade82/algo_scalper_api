# frozen_string_literal: true

module Portfolio
  # Monitors portfolio PnL and locks in profits by enforcing a trailing floor.
  # If PnL falls below the locked floor, it triggers a global exit.
  class ProfitLockEngine
    REDIS_KEY = "portfolio:profit_lock_state"
    
    # Milestone-based floor configuration
    # Example: If PnL hits 10k, floor is locked at 6k.
    DEFAULT_LEVELS = [
      { trigger: 10_000, lock: 6_000 },
      { trigger: 20_000, lock: 14_000 },
      { trigger: 30_000, lock: 22_000 },
      { trigger: 40_000, lock: 32_000 },
      { trigger: 50_000, lock: 42_000 }
    ].freeze

    class << self
      def evaluate!
        pnl_state = PnlTracker.refresh!
        total_pnl = pnl_state[:total]
        
        state = current_state
        
        # Determine if we've hit a new milestone level
        new_level = determine_level(total_pnl)
        
        if new_level > state[:level]
          state[:level] = new_level
          # Monotonic update: only increase the floor
          new_floor = DEFAULT_LEVELS[new_level - 1][:lock]
          state[:locked_floor] = [state[:locked_floor].to_f, new_floor].max
          state[:last_milestone_at] = Time.current
          
          save_state(state)
          
          Rails.logger.info("[ProfitLock] Milestone reached: Level #{new_level}. PnL=₹#{total_pnl}. Floor locked at ₹#{state[:locked_floor]}.")
          
          # Optional: Notify via Telegram on milestone
          notify_milestone(new_level, total_pnl, state[:locked_floor])
        end

        # Check for drawdown breach
        check_breach!(total_pnl, state)
      end

      def current_state
        raw = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')).get(REDIS_KEY)
        if raw
          JSON.parse(raw).symbolize_keys
        else
          { level: 0, locked_floor: 0.0, last_milestone_at: nil }
        end
      rescue StandardError => e
        Rails.logger.error("[ProfitLock] Failed to fetch state: #{e.message}")
        { level: 0, locked_floor: 0.0, last_milestone_at: nil }
      end

      # Manual reset for next trading day (or via scheduled task)
      def reset!
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')).del(REDIS_KEY)
        Rails.logger.info("[ProfitLock] State reset.")
      end

      private

      def determine_level(pnl)
        DEFAULT_LEVELS.count { |l| pnl >= l[:trigger] }
      end

      def check_breach!(total_pnl, state)
        floor = state[:locked_floor].to_f
        return if floor <= 0

        if total_pnl <= floor
          Rails.logger.warn("[ProfitLock] BREACH DETECTED: PnL ₹#{total_pnl} <= Floor ₹#{floor}. Triggering DrawdownGuard!")
          DrawdownGuard.trigger_global_exit!(total_pnl: total_pnl, floor: floor)
        end
      end

      def save_state(state)
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')).set(REDIS_KEY, state.to_json)
      end

      def notify_milestone(level, pnl, floor)
        # Check if TelegramNotifier is available
        return unless defined?(::TelegramNotifier)
        
        msg = "🎯 *PnL Milestone Reached*\n" \
              "Level: #{level}\n" \
              "Current PnL: ₹#{pnl.round(2)}\n" \
              "Locked Floor: ₹#{floor.round(2)}"
        
        ::TelegramNotifier.send_message(msg) rescue nil
      end
    end
  end
end
