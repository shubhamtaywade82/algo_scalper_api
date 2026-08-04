#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test fake WebSocket (MockDataService) and print ticks to console
# Usage: bin/rails runner script/fake_websocket_console.rb

require_relative '../config/environment'

puts "\n#{'=' * 80}"
puts '  Fake WebSocket Console - MockDataService Test'
puts '=' * 80
puts "\nStarting MockDataService...\n\n"

# Start the mock data service
mock_service = Live::MockDataService.instance
mock_service.start!

unless mock_service.running?
  puts '❌ Failed to start MockDataService'
  exit 1
end

puts '✅ MockDataService started'
puts "\n#{'-' * 80}"
puts 'Listening for ticks (press Ctrl+C to stop)...'
puts "#{'-' * 80}\n\n"

# Demonstrate TickCache access
last_ticks = {}
tick_count = 0
index_names = { '13' => 'NIFTY', '25' => 'BANKNIFTY', '51' => 'SENSEX' }

begin
  loop do
    sleep 0.5 # Check every 500ms for faster updates

    # Method 1: Access individual ticks using TickCache.get()
    %w[13 25 51].each do |security_id|
      tick = Live::TickCache.get('IDX_I', security_id)
      next unless tick

      ltp = tick[:ltp] || tick['ltp']
      next unless ltp

      # Only print if value changed
      cache_key = "IDX_I:#{security_id}"
      next unless last_ticks[cache_key] != ltp

      tick_count += 1
      index_name = index_names[security_id] || "UNKNOWN(#{security_id})"

      timestamp = Time.current.strftime('%H:%M:%S')
      puts "[#{timestamp}] #{index_name.ljust(12)} | Segment: IDX_I | Security ID: #{security_id.ljust(4)} | LTP: ₹#{ltp.to_f.round(2)}"

      # Method 2: Demonstrate direct LTP access using TickCache.ltp()
      direct_ltp = Live::TickCache.ltp('IDX_I', security_id)
      puts "                      └─ Direct LTP access: ₹#{direct_ltp.to_f.round(2)}" if direct_ltp

      last_ticks[cache_key] = ltp
    end

    # Every 10 ticks, show a summary using TickCache.all
    next unless tick_count.positive? && (tick_count % 10).zero?

    puts "\n#{'-' * 80}"
    puts 'TickCache Summary (using TickCache.all):'
    puts '-' * 80

    all_ticks = Live::TickCache.all
    if all_ticks.any?
      all_ticks.each do |key, tick_data|
        _, security_id = key.split(':')
        ltp = tick_data[:ltp] || tick_data['ltp']
        index_name = index_names[security_id] || "UNKNOWN(#{security_id})"

        puts "  #{index_name.ljust(12)} | Key: #{key.ljust(20)} | LTP: ₹#{ltp.to_f.round(2)}" if ltp
      end
    else
      puts '  No ticks in cache yet'
    end
    puts "#{'-' * 80}\n"
  end
rescue Interrupt
  puts "\n\n#{'-' * 80}"
  puts 'Stopping MockDataService...'
  mock_service.stop!
  puts '✅ Stopped'
  puts "\nTotal ticks received: #{tick_count}"
  puts "#{'=' * 80}\n"
end
