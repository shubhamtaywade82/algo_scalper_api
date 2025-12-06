# frozen_string_literal: true

# Test the new TelegramNotifier API and ApplicationService helpers
# Usage: rails runner scripts/test_new_telegram_api.rb

require_relative '../config/environment'

puts '=' * 70
puts 'Testing New TelegramNotifier API'
puts '=' * 70
puts

# Test 1: Direct TelegramNotifier class methods
puts 'Test 1: Direct TelegramNotifier.send_message...'
begin
  TelegramNotifier.send_message('🧪 Direct test from TelegramNotifier class method')
  puts '✅ Direct send_message works'
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
end

puts

# Test 2: ApplicationService helper
puts 'Test 2: ApplicationService notify() helper...'
begin
  class TestService < ApplicationService
    def call
      notify('This is a test message from ApplicationService helper', tag: 'TEST')
    end
  end

  TestService.call
  puts '✅ ApplicationService.notify() works'
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
end

puts

# Test 3: ApplicationService typing_ping
puts 'Test 3: ApplicationService typing_ping() helper...'
begin
  class TestService2 < ApplicationService
    def call
      typing_ping
      sleep 2
      notify('Message after typing indicator')
    end
  end

  TestService2.call
  puts '✅ ApplicationService.typing_ping() works'
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
end

puts

# Test 4: Backward compatibility - old Singleton interface
puts 'Test 4: Backward compatibility (Notifications::TelegramNotifier.instance)...'
begin
  notifier = Notifications::TelegramNotifier.instance
  if notifier.enabled?
    notifier.send_test_message('Test from old Singleton interface')
    puts '✅ Backward compatibility works'
  else
    puts '⚠️  Telegram not enabled'
  end
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(3).map { |l| "   #{l}" }.join("\n")
end

puts

# Test 5: Message chunking (long message)
puts 'Test 5: Message chunking (long message > 4000 chars)...'
begin
  long_message = "This is a very long message. " * 200 # ~5000 chars
  TelegramNotifier.send_message(long_message)
  puts '✅ Message chunking works'
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
end

puts
puts '=' * 70
puts 'All tests completed!'
puts '=' * 70
puts
puts 'Check your Telegram chat to verify messages were received.'

