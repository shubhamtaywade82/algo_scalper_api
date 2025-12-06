# frozen_string_literal: true

require 'singleton'

module Notifications
  # Telegram notification service for bot actions
  # Sends notifications for entry, exit, PnL updates, and risk alerts
  class TelegramNotifier
    include Singleton

    def initialize
      @bot_token = ENV['TELEGRAM_BOT_TOKEN']
      @chat_id = ENV['TELEGRAM_CHAT_ID']
      @enabled = @bot_token.present? && @chat_id.present?
      @client = nil
      @mutex = Mutex.new
      @last_pnl_notification = {} # tracker_id => timestamp (throttle PnL updates)
      @pnl_notification_interval = 300 # 5 minutes between PnL updates per position
    end

    def enabled?
      @enabled
    end

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
        if last_notification && (Time.current - last_notification) < @pnl_notification_interval
          return
        end
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

    private

    def client
      return nil unless enabled?

      @mutex.synchronize do
        @client ||= Telegram::Bot::Client.new(@bot_token) if @bot_token.present?
      end
    end

    def send_message(text)
      return unless enabled? && text.present?

      @mutex.synchronize do
        client&.api&.send_message(chat_id: @chat_id, text: text, parse_mode: 'HTML')
      end
    rescue StandardError => e
      Rails.logger.error("[TelegramNotifier] Send message failed: #{e.class} - #{e.message}")
    end

    def format_entry_message(tracker, entry_data)
      symbol = tracker.symbol || entry_data[:symbol] || 'N/A'
      entry_price = tracker.entry_price&.to_f || entry_data[:entry_price] || 0.0
      quantity = tracker.quantity || entry_data[:quantity] || 0
      direction = tracker.direction || entry_data[:direction] || 'BUY'
      index_key = tracker.index_key || entry_data[:index_key] || 'N/A'
      risk_pct = entry_data[:risk_pct]
      sl_price = entry_data[:sl_price]
      tp_price = entry_data[:tp_price]

      emoji = direction.to_s.upcase == 'BUY' ? '🟢' : '🔴'
      direction_text = direction.to_s.upcase == 'BULLISH' ? 'BUY' : direction.to_s.upcase

      message = "#{emoji} <b>ENTRY</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "📈 <b>Index:</b> #{index_key}\n"
      message += "💰 <b>Entry Price:</b> ₹#{entry_price.round(2)}\n"
      message += "📦 <b>Quantity:</b> #{quantity}\n"
      message += "🎯 <b>Direction:</b> #{direction_text}\n"

      if risk_pct
        message += "⚖️ <b>Risk:</b> #{(risk_pct * 100).round(2)}%\n"
      end

      if sl_price && tp_price
        message += "🛑 <b>SL:</b> ₹#{sl_price.round(2)}\n"
        message += "🎯 <b>TP:</b> ₹#{tp_price.round(2)}\n"
      end

      message += "🆔 <b>Order No:</b> #{tracker.order_no}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"

      message
    end

    def format_exit_message(tracker, exit_reason, exit_price, pnl)
      symbol = tracker.symbol || 'N/A'
      entry_price = tracker.entry_price&.to_f || 0.0
      exit_price_value = exit_price&.to_f || tracker.exit_price&.to_f || 0.0
      quantity = tracker.quantity || 0
      pnl_value = pnl&.to_f || tracker.last_pnl_rupees&.to_f || 0.0
      pnl_pct = tracker.last_pnl_pct&.to_f || 0.0

      # Determine emoji based on PnL
      emoji = if pnl_value.positive?
                '✅'
              elsif pnl_value.negative?
                '❌'
              else
                '⚪'
              end

      message = "#{emoji} <b>EXIT</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "💰 <b>Entry:</b> ₹#{entry_price.round(2)}\n"
      message += "💵 <b>Exit:</b> ₹#{exit_price_value.round(2)}\n"
      message += "📦 <b>Quantity:</b> #{quantity}\n"
      message += "💸 <b>PnL:</b> ₹#{pnl_value.round(2)}"

      if pnl_pct != 0.0
        pnl_pct_emoji = pnl_pct.positive? ? '📈' : '📉'
        message += " (#{pnl_pct_emoji} #{pnl_pct.round(2)}%)\n"
      else
        message += "\n"
      end

      message += "📝 <b>Reason:</b> #{exit_reason}\n"
      message += "🆔 <b>Order No:</b> #{tracker.order_no}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"

      message
    end

    def format_pnl_message(tracker, pnl, pnl_pct)
      symbol = tracker.symbol || 'N/A'
      entry_price = tracker.entry_price&.to_f || 0.0
      current_price = tracker.avg_price&.to_f || entry_price
      quantity = tracker.quantity || 0
      pnl_value = pnl.to_f
      pnl_pct_value = pnl_pct&.to_f || 0.0

      emoji = pnl_value.positive? ? '📈' : pnl_value.negative? ? '📉' : '➡️'

      message = "#{emoji} <b>PnL Update</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "💰 <b>Entry:</b> ₹#{entry_price.round(2)}\n"
      message += "💵 <b>Current:</b> ₹#{current_price.round(2)}\n"
      message += "💸 <b>PnL:</b> ₹#{pnl_value.round(2)}"

      if pnl_pct_value != 0.0
        message += " (#{pnl_pct_value.positive? ? '+' : ''}#{pnl_pct_value.round(2)}%)\n"
      else
        message += "\n"
      end

      message += "🆔 <b>Order No:</b> #{tracker.order_no}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"

      message
    end

    def format_milestone_message(tracker, milestone, pnl, pnl_pct)
      symbol = tracker.symbol || 'N/A'
      pnl_value = pnl.to_f
      pnl_pct_value = pnl_pct.to_f

      emoji = '🎯'

      message = "#{emoji} <b>Milestone Reached</b>\n\n"
      message += "📊 <b>Symbol:</b> #{symbol}\n"
      message += "🏆 <b>Milestone:</b> #{milestone}\n"
      message += "💸 <b>PnL:</b> ₹#{pnl_value.round(2)} (#{pnl_pct_value.positive? ? '+' : ''}#{pnl_pct_value.round(2)}%)\n"
      message += "🆔 <b>Order No:</b> #{tracker.order_no}\n"
      message += "⏰ <b>Time:</b> #{Time.current.strftime('%H:%M:%S')}"

      message
    end

    def format_risk_alert(message, severity)
      emoji = case severity
              when 'error'
                '🚨'
              when 'warning'
                '⚠️'
              else
                'ℹ️'
              end

      "#{emoji} <b>Risk Alert</b>\n\n#{message}\n\n⏰ #{Time.current.strftime('%H:%M:%S')}"
    end
  end
end
