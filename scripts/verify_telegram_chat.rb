# frozen_string_literal: true

# Verify Telegram chat ID and get recent messages
# Usage: rails runner scripts/verify_telegram_chat.rb

require_relative '../config/environment'

bot_token = ENV['TELEGRAM_BOT_TOKEN']
chat_id = ENV['TELEGRAM_CHAT_ID']

unless bot_token
  puts '❌ TELEGRAM_BOT_TOKEN not set'
  exit 1
end

begin
  require 'telegram/bot'
  client = Telegram::Bot::Client.new(bot_token)

  puts '=' * 70
  puts 'Telegram Chat Verification'
  puts '=' * 70
  puts

  # Get bot info
  bot_info = client.api.get_me
  bot_username = bot_info['result']['username']
  bot_name = bot_info['result']['first_name']

  puts "🤖 Bot Information:"
  puts "   Username: @#{bot_username}"
  puts "   Name: #{bot_name}"
  puts "   Bot ID: #{bot_info['result']['id']}"
  puts

  # Get recent updates to find chat IDs
  puts "📬 Recent Updates (last 10):"
  puts '-' * 70

  updates = client.api.get_updates(limit: 10, timeout: 1)

  if updates['result'].empty?
    puts "   ⚠️  No recent updates found"
    puts
    puts "   💡 To get your chat ID:"
    puts "      1. Send a message to @#{bot_username}"
    puts "      2. Run this script again"
    puts "      3. Or visit: https://api.telegram.org/bot#{bot_token}/getUpdates"
  else
    updates['result'].each_with_index do |update, idx|
      if update['message']
        msg = update['message']
        chat = msg['chat']
        puts "   Update #{idx + 1}:"
        puts "      Chat ID: #{chat['id']}"
        puts "      Chat Type: #{chat['type']}"
        puts "      From: #{chat['first_name']} #{chat['last_name'] || ''}".strip
        puts "      Username: @#{chat['username']}" if chat['username']
        puts "      Text: #{msg['text']&.truncate(50)}"
        puts
      end
    end
  end

  puts
  puts "📋 Current Configuration:"
  puts '-' * 70
  puts "   Configured Chat ID: #{chat_id || 'NOT SET'}"
  puts

  if chat_id
    # Try to get chat info
    puts "🔍 Testing configured chat ID (#{chat_id}):"
    puts '-' * 70

    begin
      # Try to get chat member info (for groups/channels) or just send a test
      test_msg = "✅ Chat verification successful!\n\n" \
                 "Your chat ID (#{chat_id}) is correct.\n" \
                 "Time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"

      result = client.api.send_message(
        chat_id: chat_id,
        text: test_msg
      )

      puts "   ✅ Message sent successfully!"
      puts "   → Message ID: #{result['result']['message_id']}"
      puts "   → Check your Telegram chat NOW!"
      puts
      puts "   If you don't see the message:"
      puts "   1. Make sure you're checking the chat with @#{bot_username}"
      puts "   2. Make sure you've sent /start to the bot"
      puts "   3. Check if the bot is blocked"
      puts "   4. Verify the chat ID matches one from the updates above"

    rescue Telegram::Bot::Exceptions::ResponseError => e
      puts "   ❌ Failed to send to chat ID #{chat_id}"
      puts "   → Error: #{e.message}"
      puts

      if e.message.include?('chat not found') || e.message.include?('400')
        puts "   💡 The chat ID might be wrong. Try:"
        puts "      1. Send a message to @#{bot_username}"
        puts "      2. Check the updates above for the correct chat ID"
        puts "      3. Update your TELEGRAM_CHAT_ID environment variable"
      end
    end
  else
    puts "   ⚠️  No chat ID configured"
    puts "   → Set TELEGRAM_CHAT_ID in your .env file"
  end

  puts
  puts '=' * 70

rescue LoadError => e
  puts "❌ Failed to load telegram-bot gem: #{e.message}"
  puts "   → Run: bundle install"
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).map { |l| "   #{l}" }.join("\n")
end

