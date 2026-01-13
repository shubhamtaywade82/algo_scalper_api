# frozen_string_literal: true

# Simple Telegram test - sends a plain text message
# Usage: rails runner scripts/test_telegram_simple.rb

require_relative '../config/environment'

bot_token = ENV.fetch('TELEGRAM_BOT_TOKEN', nil)
chat_id = ENV.fetch('TELEGRAM_CHAT_ID', nil)

unless bot_token && chat_id
  puts '❌ Missing environment variables!'
  puts "   TELEGRAM_BOT_TOKEN: #{bot_token ? 'Set' : 'NOT SET'}"
  puts "   TELEGRAM_CHAT_ID: #{chat_id ? 'Set' : 'NOT SET'}"
  exit 1
end

begin
  require 'telegram/bot'
  client = Telegram::Bot::Client.new(bot_token)

  # Send a simple plain text message (no HTML)
  puts "Sending simple test message to chat #{chat_id}..."

  result = client.api.send_message(
    chat_id: chat_id,
    text: "🧪 Simple Test Message\n\nThis is a plain text test.\nTime: #{Time.current.strftime('%H:%M:%S')}"
  )

  puts "✅ Message sent! ID: #{result['result']['message_id']}"
  puts "✅ Check your Telegram chat with @#{client.api.get_me['result']['username']}"

  # Also try with HTML
  sleep 2
  puts "\nSending HTML formatted message..."

  result2 = client.api.send_message(
    chat_id: chat_id,
    text: "🧪 <b>HTML Test Message</b>\n\nThis message uses HTML formatting.\nTime: #{Time.current.strftime('%H:%M:%S')}",
    parse_mode: 'HTML'
  )

  puts "✅ HTML message sent! ID: #{result2['result']['message_id']}"
rescue Telegram::Bot::Exceptions::ResponseError => e
  puts "❌ Telegram API Error: #{e.message}"

  if e.message.include?('chat not found')
    puts "\n💡 The bot can't find your chat. Try:"
    puts "   1. Send /start to your bot: @#{client.api.get_me['result']['username']}"
    puts '   2. Then run this script again'
  end
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).map { |l| "   #{l}" }.join("\n")
end
