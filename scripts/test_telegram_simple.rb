#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Telegram test - minimal test without Rails dependencies
# Usage: ruby scripts/test_telegram_simple.rb
# Make sure TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are set

require 'telegram/bot'

bot_token = ENV['TELEGRAM_BOT_TOKEN']
chat_id = ENV['TELEGRAM_CHAT_ID']

unless bot_token && chat_id
  puts "❌ ERROR: Missing environment variables!"
  puts "Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID"
  exit 1
end

puts "Testing Telegram connection..."
puts "Bot Token: #{bot_token[0..10]}..." if bot_token
puts "Chat ID: #{chat_id}"
puts

begin
  bot = Telegram::Bot::Client.new(bot_token)
  message = "🧪 <b>Simple Test</b>\n\nThis is a simple test from Algo Scalper API.\n\n⏰ #{Time.now.strftime('%H:%M:%S')}"
  
  response = bot.api.send_message(
    chat_id: chat_id,
    text: message,
    parse_mode: 'HTML'
  )
  
  puts "✅ SUCCESS! Message sent!"
  puts "Message ID: #{response['result']['message_id']}"
  puts "Check your Telegram for the message."
rescue Telegram::Bot::Exceptions::ResponseError => e
  puts "❌ ERROR: #{e.class}"
  puts "Message: #{e.message}"
  puts "Error Code: #{e.error_code}" if e.respond_to?(:error_code)
  puts "Description: #{e.description}" if e.respond_to?(:description)
  
  case e.error_code
  when 401
    puts "\n💡 Tip: Check that your bot token is correct"
  when 400
    puts "\n💡 Tip: Check that your chat ID is correct and you've messaged the bot"
  when 403
    puts "\n💡 Tip: You may have blocked the bot or it doesn't have permission"
  end
rescue StandardError => e
  puts "❌ ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
