# frozen_string_literal: true

# Diagnostic script for Telegram Notifier
# Usage: rails runner scripts/diagnose_telegram.rb

require_relative '../config/environment'

puts '=' * 70
puts 'Telegram Notifier Diagnostic Tool'
puts '=' * 70
puts

# Check environment variables
puts '📋 Environment Variables Check:'
puts '-' * 70

bot_token = ENV['TELEGRAM_BOT_TOKEN']
chat_id = ENV['TELEGRAM_CHAT_ID']

if bot_token.present?
  puts "✅ TELEGRAM_BOT_TOKEN: Set (#{bot_token[0..10]}...)"
else
  puts '❌ TELEGRAM_BOT_TOKEN: NOT SET'
  puts '   → Set this in your .env file or export it'
end

if chat_id.present?
  puts "✅ TELEGRAM_CHAT_ID: Set (#{chat_id})"
else
  puts '❌ TELEGRAM_CHAT_ID: NOT SET'
  puts '   → Set this in your .env file or export it'
end

puts

# Check if notifier is enabled
puts '🔍 Notifier Status:'
puts '-' * 70

notifier = Notifications::TelegramNotifier.instance

if notifier.enabled?
  puts '✅ Telegram Notifier is enabled'
else
  puts '❌ Telegram Notifier is NOT enabled'
  puts '   → Check that both TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are set'
end

puts

# Test Telegram API connection directly
if bot_token.present? && chat_id.present?
  puts '🧪 Testing Telegram API Connection:'
  puts '-' * 70

  begin
    require 'telegram/bot'
    client = Telegram::Bot::Client.new(bot_token)

    # Test 1: Get bot info
    puts 'Test 1: Getting bot information...'
    begin
      bot_info = client.api.get_me
      puts "   ✅ Bot connected successfully!"
      puts "   → Bot username: @#{bot_info['result']['username']}"
      puts "   → Bot name: #{bot_info['result']['first_name']}"
    rescue StandardError => e
      puts "   ❌ Failed to get bot info: #{e.class} - #{e.message}"
      puts "   → Check that your TELEGRAM_BOT_TOKEN is correct"
      exit 1
    end

    puts

    # Test 2: Send a test message
    puts "Test 2: Sending test message to chat ID: #{chat_id}..."
    begin
      test_message = "🧪 <b>Test Message</b>\n\n" \
                     "This is a diagnostic test from the Telegram Notifier.\n\n" \
                     "If you received this, your configuration is correct! ✅\n\n" \
                     "⏰ #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"

      result = client.api.send_message(
        chat_id: chat_id,
        text: test_message,
        parse_mode: 'HTML'
      )

      puts "   ✅ Message sent successfully!"
      puts "   → Message ID: #{result['result']['message_id']}"
      puts "   → Check your Telegram chat now!"
    rescue Telegram::Bot::Exceptions::ResponseError => e
      puts "   ❌ Failed to send message: #{e.class}"
      puts "   → Error: #{e.message}"

      if e.message.include?('chat not found') || e.message.include?('400')
        puts
        puts "   💡 Troubleshooting:"
        puts "   1. Make sure you've sent at least one message to your bot"
        puts "   2. Verify your TELEGRAM_CHAT_ID is correct"
        puts "   3. To get your chat ID:"
        puts "      - Send a message to your bot"
        puts "      - Visit: https://api.telegram.org/bot#{bot_token}/getUpdates"
        puts "      - Look for 'chat':{'id': <your_chat_id>}"
      elsif e.message.include?('401') || e.message.include?('Unauthorized')
        puts
        puts "   💡 Troubleshooting:"
        puts "   1. Check that your TELEGRAM_BOT_TOKEN is correct"
        puts "   2. Get a new token from @BotFather if needed"
      end
    rescue StandardError => e
      puts "   ❌ Unexpected error: #{e.class} - #{e.message}"
      puts "   → Backtrace: #{e.backtrace.first(3).join("\n   → ")}"
    end

    puts

    # Test 3: Send typing indicator
    puts 'Test 3: Sending typing indicator...'
    begin
      client.api.send_chat_action(chat_id: chat_id, action: 'typing')
      puts '   ✅ Typing indicator sent successfully!'
      puts '   → You should see "typing..." in your Telegram chat'
    rescue StandardError => e
      puts "   ❌ Failed to send typing indicator: #{e.class} - #{e.message}"
    end

  rescue LoadError => e
    puts "❌ Failed to load telegram-bot gem: #{e.message}"
    puts "   → Run: bundle install"
  end
else
  puts '⚠️  Skipping API tests - environment variables not set'
  puts
  puts '📝 Setup Instructions:'
  puts '-' * 70
  puts '1. Create a Telegram bot:'
  puts '   - Open Telegram and search for @BotFather'
  puts '   - Send /newbot and follow instructions'
  puts '   - Copy the bot token'
  puts
  puts '2. Get your Chat ID:'
  puts '   - Send a message to your bot'
  puts '   - Visit: https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates'
  puts '   - Find "chat":{"id": <your_chat_id>} in the response'
  puts '   - Or use @userinfobot to get your chat ID'
  puts
  puts '3. Add to .env file:'
  puts '   TELEGRAM_BOT_TOKEN=your_bot_token_here'
  puts '   TELEGRAM_CHAT_ID=your_chat_id_here'
  puts
  puts '4. Restart your Rails server/console'
end

puts
puts '=' * 70
puts 'Diagnostic complete!'
puts '=' * 70

