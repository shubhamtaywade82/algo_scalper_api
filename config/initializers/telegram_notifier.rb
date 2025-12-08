# frozen_string_literal: true

# Load Telegram notifier (simple Net::HTTP implementation)
require_relative '../../lib/telegram_notifier'

# Load backward-compatible wrapper (if needed)
begin
  require 'telegram/bot'
  require_relative '../../lib/notifications/telegram_notifier'
rescue LoadError => e
  Rails.logger.warn("[TelegramNotifier] Failed to load Telegram gem (optional): #{e.message}") if defined?(Rails)
end
