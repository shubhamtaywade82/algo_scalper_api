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

    def handle_regime_transition(from_regime, _to_regime)
      config = AlgoConfig.fetch[:telegram] || {}
      return unless config[:enabled] != false && config[:notify_no_trade_sessions] != false
      return unless Notifications::TelegramNotifier.instance.enabled?

      regime_cfg = Live::TimeRegimeService.instance.regime_config(from_regime)
      return unless regime_cfg.is_a?(Hash) && regime_cfg[:start] && regime_cfg[:end]

      start_time = Time.zone.parse(regime_cfg[:start])
      end_time = Time.zone.parse(regime_cfg[:end])
      return if PositionTracker.where(created_at: start_time..end_time).any?

      signals = Strategies::Signal.where(created_at: start_time..end_time)
      regime_label = from_regime.to_s.tr('_', ' ').upcase

      if signals.none?
        Notifications::TelegramNotifier.instance.send_message("<b>No Trades in Session: #{regime_label}</b>\n\nNo strategy signals were generated.")
        return
      end

      msg = build_session_summary_message(regime_label, signals)
      Notifications::TelegramNotifier.instance.send_message(msg)
    rescue StandardError => e
      Rails.logger.error("[StatsNotifier] handle_regime_transition error: #{e.class} - #{e.message}")
    end

    def build_session_summary_message(regime_label, signals)
      total = signals.count
      holds = signals.where(outcome: 'ignored_hold').or(signals.where(action: 'hold')).count
      blocked = signals.where(outcome: 'blocked_by_guard').count

      reasons = Hash.new(0)
      signals.where(outcome: 'blocked_by_guard').find_each do |sig|
        r = sig.metadata&.dig('entry_result_reason').presence || sig.reason
        reasons[r] += 1 if r.present?
      end

      lines = [
        "<b>No Trades in Session: #{regime_label}</b>",
        "<b>Total Signals:</b> #{total}",
        "<b>Filtered (Holds):</b> #{holds}",
        "<b>Blocked by Guards:</b> #{blocked}"
      ]
      reasons.each { |r, c| lines << "#{r}: #{c} times" }
      lines.join("\n")
    end
  end
end
