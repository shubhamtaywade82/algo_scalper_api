# frozen_string_literal: true

# Test script for Telegram Notifier
# Usage: rails runner scripts/test_telegram_notifier.rb

require_relative '../config/environment'

puts '=' * 60
puts 'Telegram Notifier Test Script'
puts '=' * 60
puts

# Check if Telegram is enabled
notifier = Notifications::TelegramNotifier.instance

unless notifier.enabled?
  puts '❌ Telegram Notifier is not enabled!'
  puts
  puts 'Please set the following environment variables:'
  puts '  - TELEGRAM_BOT_TOKEN'
  puts '  - TELEGRAM_CHAT_ID'
  puts
  exit 1
end

puts '✅ Telegram Notifier is enabled'
puts

# Test 1: Send typing indicator
puts 'Test 1: Sending typing indicator (5 seconds)...'
begin
  notifier.send_typing_indicator(duration: 5)
  puts '✅ Typing indicator sent successfully'
rescue StandardError => e
  puts "❌ Failed to send typing indicator: #{e.class} - #{e.message}"
end
puts

# Test 2: Send test message
puts 'Test 2: Sending test message...'
begin
  test_message = "This is a test message from the Telegram Notifier.\n\n" \
                 "If you received this, the notifier is working correctly! 🎉"
  notifier.send_test_message(test_message)
  puts '✅ Test message sent successfully'
rescue StandardError => e
  puts "❌ Failed to send test message: #{e.class} - #{e.message}"
end
puts

# Test 3: Send another message after typing
puts 'Test 3: Sending typing indicator followed by message...'
begin
  puts '  → Sending typing indicator (3 seconds)...'
  notifier.send_typing_indicator(duration: 3)
  puts '  → Sending follow-up message...'
  notifier.send_test_message('This message was sent after showing typing indicator! ✨')
  puts '✅ Typing indicator + message sent successfully'
rescue StandardError => e
  puts "❌ Failed: #{e.class} - #{e.message}"
end
puts

# Test 4: Send risk alert
puts 'Test 4: Sending risk alert notification...'
begin
  notifier.notify_risk_alert('This is a test risk alert message', severity: 'info')
  puts '✅ Risk alert sent successfully'
rescue StandardError => e
  puts "❌ Failed to send risk alert: #{e.class} - #{e.message}"
end
puts

puts '=' * 60
puts 'Test completed!'
puts '=' * 60
puts
puts 'Check your Telegram chat to verify all messages were received.'

