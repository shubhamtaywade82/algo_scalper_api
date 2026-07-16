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
      @last_regime = nil
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
            @last_regime = nil
          end

          # Check if regime changed
          current_regime = Live::TimeRegimeService.instance.current_regime
          if @last_regime && @last_regime != current_regime
            handle_regime_transition(@last_regime, current_regime)
          end
          @last_regime = current_regime

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

    def handle_regime_transition(old_regime, new_regime)
      config = AlgoConfig.fetch[:telegram] || {}
      return unless config[:notify_no_trade_sessions] != false

      active_regimes = %i[open_expansion trend_continuation chop_decay close_gamma]
      return unless active_regimes.include?(old_regime.to_sym)
      return if new_regime.to_sym == :pre_market || (new_regime.to_sym == :post_market && Time.zone.now.hour < 9)

      cfg = Live::TimeRegimeService.instance.regime_config(old_regime)
      start_time_str = cfg[:start]
      end_time_str = cfg[:end]
      return unless start_time_str && end_time_str

      start_time = Time.zone.parse(start_time_str)
      end_time = Time.zone.parse(end_time_str)

      # Check if any trades were executed in this window
      trades_count = PositionTracker.where(created_at: start_time..end_time).count
      if trades_count.zero?
        send_no_trade_session_report(old_regime, start_time, end_time)
      end
    rescue StandardError => e
      Rails.logger.error("[StatsNotifier] handle_regime_transition error: #{e.class} - #{e.message}")
    end

    def send_no_trade_session_report(regime, start_time, end_time)
      # Fetch signals during the session
      signals = Strategies::Signal.where(created_at: start_time..end_time)

      total_signals = signals.count
      ignored_holds = signals.where(outcome: 'ignored_hold').count
      blocked_signals = signals.where(outcome: 'blocked_by_guard')

      # Group blocked reasons
      block_reasons = Hash.new(0)
      blocked_signals.each do |s|
        reason = s.metadata['entry_result_reason'] || s.reason || 'unknown reason'
        block_reasons[reason] += 1
      end

      # Sort reasons by frequency
      sorted_reasons = block_reasons.sort_by { |_, count| -count }.first(3)

      # Build the Telegram message
      regime_label = regime.to_s.upcase.tr('_', ' ')
      message = "ℹ️ <b>No Trades in Session: #{regime_label}</b>\n"
      message += "⏰ <b>Time:</b> #{start_time.strftime('%H:%M')} - #{end_time.strftime('%H:%M')} IST\n\n"

      if total_signals.zero?
        message += "• No strategy signals were generated during this session.\n"
      else
        message += "• <b>Total Signals:</b> #{total_signals}\n"
        message += "• <b>Filtered (Holds):</b> #{ignored_holds}\n"
        message += "• <b>Blocked by Guards:</b> #{blocked_signals.count}\n"

        if sorted_reasons.any?
          message += "\n<b>Top Block Reasons:</b>\n"
          sorted_reasons.each do |reason, count|
            message += "  - #{reason}: #{count} times\n"
          end
        end
      end

      message += "\n⏰ Sent at: #{Time.current.strftime('%H:%M:%S')}"

      Notifications::TelegramNotifier.instance.send_message(message)
      Rails.logger.info("[StatsNotifier] Sent no-trade session report for #{regime_label} to Telegram")
    rescue StandardError => e
      Rails.logger.error("[StatsNotifier] Failed to send no-trade session report: #{e.class} - #{e.message}")
    end
  end
end
