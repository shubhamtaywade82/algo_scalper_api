# frozen_string_literal: true

require 'cgi'
require 'singleton'
require_relative '../telegram_notifier'

module Notifications
  # Telegram notification service for bot actions
  # Sends notifications for entry, exit, PnL updates, and risk alerts
  # This is a wrapper around the simpler TelegramNotifier class for backward compatibility
  class TelegramNotifier
    include Singleton

    DAILY_PROFIT_NOTIFY_REDIS_PREFIX = 'daily_limits:telegram:daily_profit_cap'
    DAILY_PROFIT_NOTIFY_TTL_SECONDS = 26.hours.to_i

    def initialize
      @last_pnl_notification = {} # tracker_id => timestamp (throttle PnL updates)
      @pnl_notification_interval = 300 # 5 minutes between PnL updates per position
    end

    delegate :enabled?, to: :'::TelegramNotifier'

    # Send entry notification
    # @param tracker [PositionTracker] Position tracker
    # @param entry_data [Hash] Entry details (symbol, entry_price, quantity, direction, etc.)
    def notify_entry(tracker, entry_data = {})
      return unless enabled?

      message = format_entry_message(tracker, entry_data)
      send_message(message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send entry notification: #{e.class} - #{e.message}")
    end

    # Send exit notification
    # @param tracker [PositionTracker] Position tracker
    # @param exit_reason [String] Reason for exit
    # @param exit_price [BigDecimal, Float, nil] Exit price
    # @param pnl [BigDecimal, Float, nil] Final PnL
    def notify_exit(tracker, exit_reason:, exit_price: nil, pnl: nil)
      return unless enabled?

      message = format_exit_message(tracker, exit_reason, exit_price, pnl)
      send_message(message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send exit notification: #{e.class} - #{e.message}")
    end

    # Send PnL update notification (throttled per position)
    # @param tracker [PositionTracker] Position tracker
    # @param pnl [BigDecimal, Float] Current PnL
    # @param pnl_pct [BigDecimal, Float, nil] PnL percentage
    # @param force [Boolean] Force send even if throttled
    def notify_pnl_update(tracker, pnl:, pnl_pct: nil, force: false)
      return unless enabled?

      # Throttle PnL updates per position
      unless force
        last_notification = @last_pnl_notification[tracker.id]
        return if last_notification && (Time.current - last_notification) < @pnl_notification_interval
      end

      message = format_pnl_message(tracker, pnl, pnl_pct)
      send_message(message)
      @last_pnl_notification[tracker.id] = Time.current
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send PnL notification: #{e.class} - #{e.message}")
    end

    # Send significant PnL milestone notification (e.g., +10%, +20%, etc.)
    # @param tracker [PositionTracker] Position tracker
    # @param milestone [String] Milestone description (e.g., "10% profit", "20% profit")
    # @param pnl [BigDecimal, Float] Current PnL
    # @param pnl_pct [BigDecimal, Float] PnL percentage
    def notify_pnl_milestone(tracker, milestone:, pnl:, pnl_pct:)
      return unless enabled?

      message = format_milestone_message(tracker, milestone, pnl, pnl_pct)
      send_message(message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send milestone notification: #{e.class} - #{e.message}")
    end

    # Send risk alert notification
    # @param message [String] Alert message
    # @param severity [String] Alert severity (info, warning, error)
    def notify_risk_alert(message, severity: 'warning')
      return unless enabled?

      formatted_message = format_risk_alert(message, severity)
      send_message(formatted_message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send risk alert: #{e.class} - #{e.message}")
    end

    # One Telegram per calendar day when global daily profit hits the configured cap (entries blocked).
    # Uses Redis SET NX so repeated can_trade? checks do not spam the chat.
    #
    # @param global_daily_profit [Numeric] realized global daily profit (rupees)
    # @param max_daily_profit [Numeric] configured cap (rupees)
    def notify_daily_profit_target_once(global_daily_profit:, max_daily_profit:)
      return unless enabled?
      return unless daily_profit_target_notify_enabled?

      return unless acquire_daily_profit_notify_slot!

      message = format_daily_profit_target_message(global_daily_profit, max_daily_profit)
      send_message(message)
    rescue StandardError => e
      Rails.logger.error(
        "[TelegramNotifier] Failed to send daily profit target notification: #{e.class} - #{e.message}"
      )
    end

    # Send error notification
    # @param message [String] Error message or exception
    # @param context [String, nil] Optional context or service name
    def notify_error(message, context: nil)
      return unless enabled?

      formatted_message = "🚨 <b>ERROR</b>\n"
      formatted_message += "<b>Context:</b> #{h(context)}\n" if context
      formatted_message += "\n#{h(message)}"
      formatted_message += "\n\n⏰ #{Time.current.strftime('%H:%M:%S')}"

      send_message(formatted_message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send error notification: #{e.class} - #{e.message}")
    end

    # Send warning notification
    # @param message [String] Warning message
    # @param context [String, nil] Optional context or service name
    def notify_warning(message, context: nil)
      return unless enabled?

      formatted_message = "⚠️ <b>WARNING</b>\n"
      formatted_message += "<b>Context:</b> #{h(context)}\n" if context
      formatted_message += "\n#{h(message)}"
      formatted_message += "\n\n⏰ #{Time.current.strftime('%H:%M:%S')}"

      send_message(formatted_message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send warning notification: #{e.class} - #{e.message}")
    end

    # Send status change notification
    # @param message [String] Status message
    # @param status [String, nil] New status
    def notify_status(message, status: nil)
      return unless enabled?

      formatted_message = "ℹ️ <b>STATUS UPDATE</b>\n"
      formatted_message += "<b>Status:</b> #{h(status.upcase)}\n" if status
      formatted_message += "\n#{h(message)}"
      formatted_message += "\n\n⏰ #{Time.current.strftime('%H:%M:%S')}"

      send_message(formatted_message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send status notification: #{e.class} - #{e.message}")
    end

    # Send typing indicator to show bot is typing
    # @param duration [Integer] Duration in seconds (default: 5)
    def send_typing_indicator(duration: 5)
      return unless enabled?

      ::TelegramNotifier.send_chat_action(action: 'typing')
      sleep(duration) if duration.positive?
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send typing indicator: #{e.class} - #{e.message}")
    end

    # Send a test message (for testing purposes)
    # @param message [String] Test message
    def send_test_message(message = 'Test message from Telegram Notifier')
      return unless enabled?

      test_msg = "🧪 <b>Test Notification</b>\n\n#{message}\n\n⏰ #{Time.current.strftime('%H:%M:%S')}"
      send_message(test_msg)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send test message: #{e.class} - #{e.message}")
    end

    # Send trading statistics notification (daily stats only)
    # @param stats [Hash, nil] Trading stats hash (from PositionTracker.paper_trading_stats_with_pct)
    #                         If nil, will fetch today's stats
    def notify_trading_stats(stats: nil)
      return unless enabled?

      # Default to today's stats only
      stats ||= PositionTracker.paper_trading_stats_with_pct(date: Time.zone.today)
      message = format_trading_stats(stats)
      send_message(message)
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Failed to send trading stats: #{e.class} - #{e.message}")
    end

    def send_message(text)
      return unless enabled? && text.present?

      # Messages are pre-formatted HTML — skip the Markdown→HTML converter to
      # prevent it from re-escaping the tags we deliberately embedded.
      ::TelegramNotifier.send_message(text, parse_mode: 'HTML', skip_formatter: true)
    end

    # Escape dynamic values so stray <, >, & characters don't break HTML parsing.
    def h(value)
      CGI.escapeHTML(value.to_s)
    end

    def format_entry_message(tracker, entry_data)
      symbol = h(tracker.symbol || entry_data[:symbol] || 'N/A')
      entry_price = tracker.entry_price&.to_f || entry_data[:entry_price] || 0.0
      quantity   = tracker.quantity || entry_data[:quantity] || 0
      direction  = tracker.direction || entry_data[:direction] || 'BUY'
      index_key  = h(tracker.index_key || entry_data[:index_key] || 'N/A')
      risk_pct   = entry_data[:risk_pct]
      sl_price   = entry_data[:sl_price]
      tp_price   = entry_data[:tp_price]

      emoji          = direction.to_s.upcase == 'BUY' ? '🟢' : '🔴'
      direction_text = direction.to_s.upcase == 'BULLISH' ? 'BUY' : h(direction.to_s.upcase)

      message  = "#{emoji} <b>ENTRY</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "📈 <b>Index:</b> #{index_key}\n"
      message += "💰 <b>Entry Price:</b> ₹#{entry_price.round(2)}\n"
      message += "📦 <b>Quantity:</b> #{quantity}\n"
      message += "🎯 <b>Direction:</b> #{direction_text}\n"
      message += "⚖️ <b>Risk:</b> #{(risk_pct * 100).round(2)}%\n" if risk_pct

      if sl_price && tp_price
        message += "🛑 <b>SL:</b> ₹#{sl_price.round(2)}\n"
        message += "🎯 <b>TP:</b> ₹#{tp_price.round(2)}\n"
      end

      message += "🆔 <b>Order No:</b> #{h(tracker.order_no)}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"
      message
    end

    def format_exit_message(tracker, exit_reason, exit_price, pnl)
      symbol           = h(tracker.symbol || 'N/A')
      entry_price      = tracker.entry_price.to_f
      exit_price_value = exit_price&.to_f || tracker.exit_price&.to_f || 0.0
      quantity         = tracker.quantity || 0
      pnl_value        = pnl&.to_f || tracker.last_pnl_rupees&.to_f || 0.0

      # Calculate PnL percentage from PnL value (includes broker fees) for consistency with exit reason
      # Exit reason shows PnL percentage (after fees), not price change percentage
      # Formula: PnL percentage = (PnL / (entry_price * quantity)) * 100
      pnl_pct = if pnl_value.present? && entry_price.positive? && quantity.positive?
                  # Calculate PnL percentage (includes fees) - matches exit reason format
                  (pnl_value / (entry_price * quantity)) * 100.0
                elsif tracker.last_pnl_pct.present?
                  # Fallback: use price change percentage from DB (convert decimal to percentage)
                  (tracker.last_pnl_pct.to_f * 100.0)
                elsif entry_price.positive? && exit_price_value.positive?
                  # Last fallback: calculate price change percentage
                  ((exit_price_value - entry_price) / entry_price) * 100.0
                else
                  0.0
                end

      emoji = if pnl_value.positive?
                '✅'
              elsif pnl_value.negative?
                '❌'
              else
                '⚪'
              end

      message  = "#{emoji} <b>EXIT</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "💰 <b>Entry:</b> ₹#{entry_price.round(2)}\n"
      message += "💵 <b>Exit:</b> ₹#{exit_price_value.round(2)}\n"
      message += "📦 <b>Quantity:</b> #{quantity}\n"
      message += "💸 <b>PnL:</b> ₹#{pnl_value.round(2)}"

      if pnl_pct.zero?
        message += "\n"
      else
        pnl_pct_emoji = pnl_pct.positive? ? '📈' : '📉'
        message += " (#{pnl_pct_emoji} #{pnl_pct.round(2)}%)\n"
      end

      message += "📝 <b>Reason:</b> #{h(exit_reason)}\n"
      message += "🆔 <b>Order No:</b> #{h(tracker.order_no)}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"

      config = AlgoConfig.fetch[:telegram] || {}
      if config[:include_stats_on_exit] == true
        message += "\n\n"
        message += format_trading_stats(PositionTracker.paper_trading_stats_with_pct(date: Time.zone.today))
      end

      message
    end

    def format_pnl_message(tracker, pnl, pnl_pct)
      symbol        = h(tracker.symbol || 'N/A')
      entry_price   = tracker.entry_price.to_f
      current_price = tracker.avg_price&.to_f || entry_price
      tracker.quantity || 0
      pnl_value     = pnl.to_f
      pnl_pct_value = pnl_pct.to_f

      emoji = if pnl_value.positive?
                '📈'
              else
                pnl_value.negative? ? '📉' : '➡️'
              end

      message  = "#{emoji} <b>PnL Update</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "💰 <b>Entry:</b> ₹#{entry_price.round(2)}\n"
      message += "💵 <b>Current:</b> ₹#{current_price.round(2)}\n"
      message += "💸 <b>PnL:</b> ₹#{pnl_value.round(2)}"
      message += if pnl_pct_value.zero?
                   "\n"
                 else
                   " (#{'+' if pnl_pct_value.positive?}#{pnl_pct_value.round(2)}%)\n"
                 end
      message += "🆔 <b>Order No:</b> #{h(tracker.order_no)}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"
      message
    end

    def format_milestone_message(tracker, milestone, pnl, pnl_pct)
      symbol        = h(tracker.symbol || 'N/A')
      pnl_value     = pnl.to_f
      pnl_pct_value = pnl_pct.to_f

      message  = "🎯 <b>Milestone Reached</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "🏆 <b>Milestone:</b> #{h(milestone)}\n"
      message += "💸 <b>PnL:</b> ₹#{pnl_value.round(2)} (#{'+' if pnl_pct_value.positive?}#{pnl_pct_value.round(2)}%)\n"
      message += "🆔 <b>Order No:</b> #{h(tracker.order_no)}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"
      message
    end

    def format_risk_alert(message, severity)
      emoji = case severity
              when 'error'   then '🚨'
              when 'warning' then '⚠️'
              else                'ℹ️'
              end

      "#{emoji} <b>Risk Alert</b>\n\n#{h(message)}\n\n⏰ #{Time.current.strftime('%H:%M:%S')}"
    end

    def daily_profit_target_notify_enabled?
      config = AlgoConfig.fetch[:telegram] || {}
      config[:enabled] != false && config[:notify_daily_profit_target] != false
    rescue StandardError
      false
    end

    def acquire_daily_profit_notify_slot!
      r = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      key = "#{DAILY_PROFIT_NOTIFY_REDIS_PREFIX}:#{Time.zone.today}"
      r.set(key, '1', nx: true, ex: DAILY_PROFIT_NOTIFY_TTL_SECONDS)
    rescue StandardError => e
      Rails.logger.warn("[TelegramNotifier] Redis lock for daily profit notify failed: #{e.message}")
      false
    end

    def format_daily_profit_target_message(global_daily_profit, max_daily_profit)
      g = global_daily_profit.to_f.round(2)
      m = max_daily_profit.to_f.round(2)
      "ℹ️ <b>Daily profit target reached</b>\n\n" \
        "<b>Global PnL:</b> ₹#{h(g)}\n" \
        "<b>Cap:</b> ₹#{h(m)}\n" \
        "<b>Action:</b> New entries blocked for the rest of the session.\n\n" \
        "⏰ #{Time.current.strftime('%H:%M:%S')}"
    end

    def format_trading_stats(stats)
      total_pnl_emoji    = stats[:total_pnl_rupees] >= 0 ? '📈' : '📉'
      realized_pnl_emoji = stats[:realized_pnl_rupees] >= 0 ? '✅' : '❌'

      message  = "📊 <b>Daily Trading Statistics</b>\n"
      message += "📅 <b>Date:</b> #{Time.zone.today.strftime('%Y-%m-%d')}\n\n"
      message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
      message += "<b>#{total_pnl_emoji} Total PnL:</b> ₹#{stats[:total_pnl_rupees].round(2)} (#{stats[:total_pnl_pct].round(2)}%)\n"
      message += "<b>#{realized_pnl_emoji} Realized PnL:</b> ₹#{stats[:realized_pnl_rupees].round(2)} (#{stats[:realized_pnl_pct].round(2)}%)\n"
      message += "<b>⏳ Unrealized PnL:</b> ₹#{stats[:unrealized_pnl_rupees].round(2)} (#{stats[:unrealized_pnl_pct].round(2)}%)\n"
      message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
      message += "<b>📊 Total Trades:</b> #{stats[:total_trades]}\n"
      message += "<b>🟢 Winners:</b> #{stats[:winners]}\n"
      message += "<b>🔴 Losers:</b> #{stats[:losers]}\n"
      message += "<b>📈 Win Rate:</b> #{stats[:win_rate].round(2)}%\n"
      message += "<b>🔄 Active Positions:</b> #{stats[:active_positions]}\n"
      message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
      message += "<b>📊 Avg Realized PnL %:</b> #{stats[:avg_realized_pnl_pct].round(2)}%\n"
      message += "<b>📊 Avg Unrealized PnL %:</b> #{stats[:avg_unrealized_pnl_pct].round(2)}%\n"
      message += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
      message += "⏰ <b>Updated:</b> #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
      message
    end
  end
end
