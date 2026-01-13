# frozen_string_literal: true

# Direct test of TelegramNotifier instance
# Usage: rails runner scripts/test_telegram_notifier_direct.rb

require_relative '../config/environment'

puts 'Testing TelegramNotifier directly...'
puts

notifier = Notifications::TelegramNotifier.instance

unless notifier.enabled?
  puts '❌ Telegram Notifier is not enabled!'
  exit 1
end

puts '✅ Notifier is enabled'
puts

# Test 1: Direct message send
puts 'Test 1: Sending message via notifier.send_test_message...'
begin
  notifier.send_test_message('Direct test from TelegramNotifier instance')
  puts '✅ Message sent via notifier'
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).map { |l| "   #{l}" }.join("\n")
end

puts

# Test 2: Typing indicator
puts 'Test 2: Sending typing indicator...'
begin
  notifier.send_typing_indicator(duration: 3)
  puts '✅ Typing indicator sent'
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
end

puts

# Test 3: Risk alert
puts 'Test 3: Sending risk alert...'
begin
  notifier.notify_risk_alert('Test risk alert from direct test', severity: 'info')
  puts '✅ Risk alert sent'
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
end

puts
puts 'Check your Telegram chat with @my_alert_system_bot'
puts 'If you still don\'t see messages:'
puts '  1. Make sure you\'ve sent /start to the bot'
puts '  2. Verify you\'re checking the correct chat'
puts '  3. Check the Rails logs for any errors'
