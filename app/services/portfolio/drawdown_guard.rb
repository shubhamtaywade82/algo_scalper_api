# frozen_string_literal: true

module Portfolio
  # Hard kill switch for portfolio-level profit protection.
  #
  # When ProfitLockEngine detects a floor breach, this guard:
  #   1. Sets an idempotency key (fires only once per trading day)
  #   2. Exits all active positions at market
  #   3. Blocks new entries for the rest of the session
  #   4. Sends a Telegram alert
  #
  # State lives in Redis (TTL-scoped to the trading session).
  class DrawdownGuard
    REDIS_URL        = ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')
    KEY_TRIGGERED    = 'portfolio:floor_breach:triggered'
    KEY_ENTRIES_BLOCKED = 'portfolio:floor_breach:entries_blocked'
    TTL = 26.hours.to_i

    class << self
      # Main entry point. Idempotent — will not fire twice per trading day.
      #
      # @param net_pnl  [Float]   portfolio net PnL at the time of breach
      # @param floor    [Float]   locked floor that was breached
      # @param level    [Integer] arm level that was active
      def trigger_global_exit!(net_pnl:, floor:, level: 0)
        r = redis
        return unless r

        # Idempotency: only fire once per day
        return if r.get(KEY_TRIGGERED) == 'true'

        r.set(KEY_TRIGGERED, 'true')
        r.expire(KEY_TRIGGERED, TTL)

        Rails.logger.warn(
          "[Portfolio::DrawdownGuard] 🚨 GLOBAL EXIT TRIGGERED — " \
          "net=₹#{net_pnl.round(2)}, floor=₹#{floor.round(2)}, level=#{level}"
        )

        exit_all_positions!(net_pnl: net_pnl, floor: floor)
        block_new_entries!
        notify_breach(net_pnl: net_pnl, floor: floor, level: level)
      rescue StandardError => e
        Notifications::TelegramNotifier.instance.notify_error(e.message, context: 'Portfolio::DrawdownGuard#trigger_global_exit!')
        Rails.logger.error("[Portfolio::DrawdownGuard] trigger_global_exit! error: #{e.class} - #{e.message}")
      end

      # True if the global exit has already been triggered today.
      # Used by: EntryPolicy, ProfitLockEngine, UnifiedExitChecker.
      #
      # @return [Boolean]
      def triggered?
        redis&.get(KEY_TRIGGERED) == 'true'
      rescue StandardError
        false
      end

      # True if entries have been blocked (subset of triggered? — same lifetime here).
      # @return [Boolean]
      def entries_blocked?
        redis&.get(KEY_ENTRIES_BLOCKED) == 'true'
      rescue StandardError
        false
      end

      # Manual reset for console use or test teardown.
      def reset_day!
        r = redis
        return unless r

        r.del(KEY_TRIGGERED)
        r.del(KEY_ENTRIES_BLOCKED)
        Portfolio::PnlTracker.reset_day!
        Portfolio::PaperPeakTracker.reset_day!

        Rails.logger.info('[Portfolio::DrawdownGuard] Daily state reset')
      rescue StandardError => e
        Notifications::TelegramNotifier.instance.notify_error(e.message, context: 'Portfolio::DrawdownGuard')
        Rails.logger.error("[Portfolio::DrawdownGuard] reset_day! error: #{e.message}")
      end

      private

      def redis
        @redis ||= Redis.new(url: REDIS_URL)
      rescue StandardError => e
        Rails.logger.error("[Portfolio::DrawdownGuard] Redis init error: #{e.message}")
        nil
      end

      # Exit all active positions at market.
      def exit_all_positions!(net_pnl:, floor:)
        active_positions = Positions::ActiveCache.instance.all_positions

        if active_positions.empty?
          Rails.logger.info('[Portfolio::DrawdownGuard] No active positions to exit.')
          return
        end

        Rails.logger.warn(
          "[Portfolio::DrawdownGuard] Exiting #{active_positions.size} positions " \
          "(net=₹#{net_pnl.round(2)}, floor=₹#{floor.round(2)})"
        )

        active_positions.each do |pos_data|
          tracker = PositionTracker.find_by(id: pos_data.tracker_id)
          next unless tracker&.active?

          begin
            exit_engine = Rails.application.config.x.trading_supervisor&.[](:exit_manager)

            if exit_engine
              exit_engine.execute_exit(tracker, 'PORTFOLIO_FLOOR_BREACH')
            else
              Rails.logger.error(
                "[Portfolio::DrawdownGuard] CANNOT force-exit tracker=#{pos_data.tracker_id} " \
                '- exit_manager unreachable, position stays active until the 5s enforcement loop catches it'
              )
            end
          rescue StandardError => e
            Rails.logger.error(
              "[Portfolio::DrawdownGuard] Exit failed for tracker=#{pos_data.tracker_id}: " \
              "#{e.class} - #{e.message}"
            )
          end
        end
      end

      # Block new entries for the trading session.
      def block_new_entries!
        r = redis
        return unless r

        r.set(KEY_ENTRIES_BLOCKED, 'true')
        r.expire(KEY_ENTRIES_BLOCKED, TTL)
        Rails.logger.info('[Portfolio::DrawdownGuard] New entries blocked for the rest of the session.')
      end

      # Send Telegram alert (best-effort — does not raise).
      def notify_breach(net_pnl:, floor:, level:)
        return unless defined?(Notifications::TelegramNotifier)
        return unless Notifications::TelegramNotifier.instance.enabled?

        msg = "🚨 *Profit Protection Triggered* (Level #{level})\n" \
              "Net PnL: ₹#{net_pnl.round(2)}\n" \
              "Locked Floor: ₹#{floor.round(2)}\n" \
              "Action: All positions exited, new entries blocked."

        Notifications::TelegramNotifier.instance.send_message(msg)
      rescue StandardError => e
        Rails.logger.warn("[Portfolio::DrawdownGuard] Telegram notify failed: #{e.message}")
      end
    end
  end
end
