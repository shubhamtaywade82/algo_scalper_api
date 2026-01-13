# frozen_string_literal: true

module Live
  # Service to send daily trading statistics to Telegram at market close
  # Sends stats once when market closes (3:30 PM IST)
  class StatsNotifierService
    include Singleton

    def initialize
      @thread = nil
      @running = false
      @lock = Mutex.new
      @stats_sent_today = false
      @last_check_date = nil
    end

    def start
      @lock.synchronize do
        return if @running

        @running = true
        @thread = Thread.new { run_loop }
        Rails.logger.info('[StatsNotifier] Started market close stats notification service')
      end
    end

    def stop
      @lock.synchronize do
        @running = false
        @thread&.kill
        @thread&.join(1)
        @thread = nil
        Rails.logger.info('[StatsNotifier] Stopped market close stats notification service')
      end
    end

    def running?
      @running
    end

    private

    def run_loop
      Thread.current.name = 'stats-notifier-service'

      loop do
        break unless @running

        begin
          # Reset daily flag if it's a new day
          today = Time.zone.today
          if @last_check_date != today
            @stats_sent_today = false
            @last_check_date = today
          end

          # Check if market close stats notifications are enabled
          config = AlgoConfig.fetch[:telegram] || {}
          enabled = config[:notify_stats_at_market_close] != false

          # Check if market has closed (3:30 PM IST)
          if enabled && Notifications::TelegramNotifier.instance.enabled? && !@stats_sent_today && TradingSession::Service.market_closed?
            send_stats
            @stats_sent_today = true
            Rails.logger.info('[StatsNotifier] Market closed - sent daily trading stats to Telegram')
          end

          # Sleep for 1 minute and check again
          sleep 60
        rescue StandardError => e
          Rails.logger.error("[StatsNotifier] Error in run_loop: #{e.class} - #{e.message}")
          sleep 60 # Continue even on error
        end
      end
    rescue StandardError => e
      Rails.logger.error("[StatsNotifier] FATAL ERROR: #{e.class} - #{e.message}")
      @running = false
    end

    def send_stats
      stats = PositionTracker.paper_trading_stats_with_pct(date: Time.zone.today)
      Notifications::TelegramNotifier.instance.notify_trading_stats(stats: stats)
      Rails.logger.info("[StatsNotifier] Sent daily trading stats to Telegram (Trades: #{stats[:total_trades]}, PnL: ₹#{stats[:realized_pnl_rupees]})")
    rescue StandardError => e
      Rails.logger.error("[StatsNotifier] Failed to send stats: #{e.class} - #{e.message}")
    end
  end
end
