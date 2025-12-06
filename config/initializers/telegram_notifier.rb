# frozen_string_literal: true

# Load Telegram bot gem and notification service
begin
  require 'telegram/bot'
  require_relative '../../lib/notifications/telegram_notifier'
rescue LoadError => e
  Rails.logger.warn("[TelegramNotifier] Failed to load Telegram gem: #{e.message}") if defined?(Rails)
end
