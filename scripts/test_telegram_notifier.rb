#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for Telegram Notifier
# Usage: 
#   rails runner scripts/test_telegram_notifier.rb
#   OR
#   rake telegram:test

# Load Rails environment
begin
  require_relative '../config/environment' unless defined?(Rails)
rescue LoadError => e
  puts "Error loading Rails environment: #{e.message}"
  puts "Please run this script with: rails runner scripts/test_telegram_notifier.rb"
  exit 1
end

puts "=" * 80
puts "Telegram Notifier Test"
puts "=" * 80
puts

# Check environment variables
bot_token = ENV['TELEGRAM_BOT_TOKEN']
chat_id = ENV['TELEGRAM_CHAT_ID']

puts "Environment Check:"
puts "  TELEGRAM_BOT_TOKEN: #{bot_token.present? ? '✓ Set' : '✗ Missing'}"
puts "  TELEGRAM_CHAT_ID: #{chat_id.present? ? '✓ Set' : '✗ Missing'}"
puts

unless bot_token.present? && chat_id.present?
  puts "❌ ERROR: Missing required environment variables!"
  puts
  puts "Please set the following in your .env file or environment:"
  puts "  TELEGRAM_BOT_TOKEN=your_bot_token"
  puts "  TELEGRAM_CHAT_ID=your_chat_id"
  puts
  puts "To get a bot token:"
  puts "  1. Message @BotFather on Telegram"
  puts "  2. Send /newbot and follow instructions"
  puts
  puts "To get your chat ID:"
  puts "  1. Message @userinfobot on Telegram"
  puts "  2. It will reply with your chat ID"
  puts
  exit 1
end

# Initialize notifier
puts "Initializing TelegramNotifier..."
begin
  notifier = Notifications::TelegramNotifier.instance
  puts "  ✓ Notifier initialized"
  puts "  Enabled: #{notifier.enabled? ? 'Yes' : 'No'}"
  puts
rescue StandardError => e
  puts "  ✗ Failed to initialize: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

unless notifier.enabled?
  puts "❌ ERROR: Notifier is not enabled!"
  puts "Check that TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are set correctly."
  exit 1
end

# Test 1: Simple message via risk alert (public method)
puts "Test 1: Sending simple test message..."
begin
  test_message = "🧪 Test Notification\n\nThis is a test message from Algo Scalper API.\n\n⏰ #{Time.current.strftime('%H:%M:%S')}"
  notifier.notify_risk_alert(test_message, severity: 'info')
  puts "  ✓ Test message sent successfully!"
  puts "  Check your Telegram for the message."
  sleep 1 # Small delay between messages
rescue StandardError => e
  puts "  ✗ Failed to send test message: #{e.class} - #{e.message}"
  puts "  Error details: #{e.message}"
  if e.respond_to?(:response) && e.response
    puts "  Response: #{e.response.inspect}"
  end
  puts e.backtrace.first(5).join("\n")
  puts
end

# Test 2: Entry notification (mock tracker)
puts "Test 2: Testing entry notification format..."
begin
  # Create a mock tracker object
  mock_tracker = OpenStruct.new(
    id: 999,
    order_no: 'TEST-ENTRY-001',
    symbol: 'NIFTY25JAN24500CE',
    entry_price: BigDecimal('125.50'),
    quantity: 50,
    direction: 'bullish',
    index_key: 'NIFTY'
  )

  entry_data = {
    symbol: 'NIFTY25JAN24500CE',
    entry_price: 125.50,
    quantity: 50,
    direction: :bullish,
    index_key: 'NIFTY',
    risk_pct: 0.01,
    sl_price: 87.85,
    tp_price: 200.80
  }

  notifier.notify_entry(mock_tracker, entry_data)
  puts "  ✓ Entry notification sent successfully!"
  puts "  Check your Telegram for the entry notification."
  puts
rescue StandardError => e
  puts "  ✗ Failed to send entry notification: #{e.class} - #{e.message}"
  if e.respond_to?(:response) && e.response
    puts "  Response: #{e.response.inspect}"
  end
  puts e.backtrace.first(5).join("\n")
  puts
end
sleep 1

# Test 3: Exit notification (mock tracker)
puts "Test 3: Testing exit notification format..."
begin
  mock_tracker = OpenStruct.new(
    id: 999,
    order_no: 'TEST-EXIT-001',
    symbol: 'NIFTY25JAN24500CE',
    entry_price: BigDecimal('125.50'),
    exit_price: BigDecimal('200.80'),
    quantity: 50,
    last_pnl_rupees: BigDecimal('3765.00'),
    last_pnl_pct: BigDecimal('60.00')
  )

  notifier.notify_exit(
    mock_tracker,
    exit_reason: 'TP HIT 60.00%',
    exit_price: 200.80,
    pnl: 3765.00
  )
  puts "  ✓ Exit notification sent successfully!"
  puts "  Check your Telegram for the exit notification."
  puts
rescue StandardError => e
  puts "  ✗ Failed to send exit notification: #{e.class} - #{e.message}"
  if e.respond_to?(:response) && e.response
    puts "  Response: #{e.response.inspect}"
  end
  puts e.backtrace.first(5).join("\n")
  puts
end
sleep 1

# Test 4: PnL milestone notification
puts "Test 4: Testing PnL milestone notification..."
begin
  mock_tracker = OpenStruct.new(
    id: 999,
    order_no: 'TEST-MILESTONE-001',
    symbol: 'NIFTY25JAN24500CE'
  )

  notifier.notify_pnl_milestone(
    mock_tracker,
    milestone: '20% profit',
    pnl: 1255.00,
    pnl_pct: 20.0
  )
  puts "  ✓ PnL milestone notification sent successfully!"
  puts "  Check your Telegram for the milestone notification."
  puts
rescue StandardError => e
  puts "  ✗ Failed to send milestone notification: #{e.class} - #{e.message}"
  if e.respond_to?(:response) && e.response
    puts "  Response: #{e.response.inspect}"
  end
  puts e.backtrace.first(5).join("\n")
  puts
end
sleep 1

# Test 5: Risk alert notification
puts "Test 5: Testing risk alert notification..."
begin
  notifier.notify_risk_alert(
    "Daily loss limit reached for NIFTY: -2.5%",
    severity: 'warning'
  )
  puts "  ✓ Risk alert notification sent successfully!"
  puts "  Check your Telegram for the risk alert."
  puts
rescue StandardError => e
  puts "  ✗ Failed to send risk alert: #{e.class} - #{e.message}"
  if e.respond_to?(:response) && e.response
    puts "  Response: #{e.response.inspect}"
  end
  puts e.backtrace.first(5).join("\n")
  puts
end
sleep 1

puts "=" * 80
puts "Test Summary"
puts "=" * 80
puts "All tests completed. Check your Telegram for notifications."
puts
puts "If you didn't receive any messages, check:"
puts "  1. Bot token is correct"
puts "  2. Chat ID is correct"
puts "  3. You've sent at least one message to the bot"
puts "  4. Bot is not blocked"
puts "=" * 80
