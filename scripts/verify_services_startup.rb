#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to verify all services start correctly on ./bin/dev or rails s
# Usage: rails runner scripts/verify_services_startup.rb

puts '=' * 80
puts 'SERVICE STARTUP VERIFICATION'
puts '=' * 80
puts ''

# Get supervisor
supervisor = Rails.application.config.x.trading_supervisor
unless supervisor
  puts '❌ ERROR: Supervisor not found in Rails.application.config.x.trading_supervisor'
  puts '   Make sure you are running this in a web server context (bin/dev or rails s)'
  exit 1
end

puts '✅ Supervisor found'
puts ''

# Check supervisor state
running = supervisor.instance_variable_get(:@running)
puts "Supervisor running flag: #{running}"
puts ''

# Get all registered services
services = supervisor.instance_variable_get(:@services) || {}
puts "Total services registered: #{services.size}"
puts ''

# Verify each service
puts '=' * 80
puts 'SERVICE STATUS CHECK'
puts '=' * 80
puts ''

all_ok = true

services.each do |name, service|
  puts "Service: #{name}"
  puts "  Class: #{service.class.name}"

  # Check if service has start method
  has_start = service.respond_to?(:start)
  puts "  Has start method: #{has_start ? '✅' : '❌'}"

  # Check if service has stop method
  has_stop = service.respond_to?(:stop)
  puts "  Has stop method: #{has_stop ? '✅' : '❌'}"

  # Check running status (if available)
  if service.respond_to?(:running?)
    running_status = service.running?
    puts "  Running: #{running_status ? '✅ YES' : '❌ NO'}"
  elsif service.respond_to?(:instance) && service.instance.respond_to?(:running?)
    # For singleton services accessed via instance
    running_status = service.instance.running?
    puts "  Running (via instance): #{running_status ? '✅ YES' : '❌ NO'}"
  else
    puts '  Running: ⚠️  N/A (no running? method)'
  end

  # Try to call start (if not running)
  if has_start
    begin
      service.start
      puts '  Start call: ✅ SUCCESS'
    rescue StandardError => e
      puts "  Start call: ❌ FAILED - #{e.class}: #{e.message}"
      all_ok = false
    end
  else
    puts '  Start call: ❌ SKIPPED (no start method)'
    all_ok = false
  end

  puts ''
end

# Check specific services
puts '=' * 80
puts 'SPECIFIC SERVICE CHECKS'
puts '=' * 80
puts ''

# 1. MarketFeedHub
puts '1. MarketFeedHub:'
hub = Live::MarketFeedHub.instance
puts "   Running: #{hub.running? ? '✅' : '❌'}"
puts "   Connected: #{hub.connected? ? '✅' : '❌'}"
puts "   Watchlist count: #{hub.instance_variable_get(:@watchlist)&.count || 0}"
puts ''

# 2. Signal::Scheduler
puts '2. Signal::Scheduler:'
scheduler = services[:signal_scheduler]
if scheduler
  running = scheduler.instance_variable_get(:@running)
  thread = scheduler.instance_variable_get(:@thread)
  puts "   Running: #{running ? '✅' : '❌'}"
  puts "   Thread alive: #{thread&.alive? ? '✅' : '❌'}"
  puts "   Thread name: #{thread&.name || 'N/A'}"
else
  puts '   ❌ Not found in supervisor'
end
puts ''

# 3. RiskManager
puts '3. RiskManager:'
risk = services[:risk_manager]
if risk
  puts "   Running: #{risk.running? ? '✅' : '❌'}"
  thread = risk.instance_variable_get(:@thread)
  puts "   Thread alive: #{thread&.alive? ? '✅' : '❌'}"
  puts "   Thread name: #{thread&.name || 'N/A'}"
else
  puts '   ❌ Not found in supervisor'
end
puts ''

# 4. ActiveCache
puts '4. ActiveCache:'
cache = Positions::ActiveCache.instance
subscription_id = cache.instance_variable_get(:@subscription_id)
puts "   Subscription ID: #{subscription_id || '❌ NONE (not started)'}"
puts "   Has subscription: #{subscription_id ? '✅' : '❌'}"
puts ''

# 5. PositionHeartbeat
puts '5. PositionHeartbeat:'
heartbeat = services[:position_heartbeat]
if heartbeat
  running = heartbeat.instance_variable_get(:@running)
  thread = heartbeat.instance_variable_get(:@thread)
  puts "   Running: #{running ? '✅' : '❌'}"
  puts "   Thread alive: #{thread&.alive? ? '✅' : '❌'}"
  puts "   Thread name: #{thread&.name || 'N/A'}"
else
  puts '   ❌ Not found in supervisor'
end
puts ''

# 6. PaperPnlRefresher
puts '6. PaperPnlRefresher:'
pnl = services[:paper_pnl_refresher]
if pnl
  running = pnl.instance_variable_get(:@running)
  thread = pnl.instance_variable_get(:@thread)
  puts "   Running: #{running ? '✅' : '❌'}"
  puts "   Thread alive: #{thread&.alive? ? '✅' : '❌'}"
  puts "   Thread name: #{thread&.name || 'N/A'}"
else
  puts '   ❌ Not found in supervisor'
end
puts ''

# 7. ExitEngine
puts '7. ExitEngine:'
exit_engine = services[:exit_manager]
if exit_engine
  running = exit_engine.instance_variable_get(:@running)
  thread = exit_engine.instance_variable_get(:@thread)
  puts "   Running: #{running ? '✅' : '❌'}"
  puts "   Thread alive: #{thread&.alive? ? '✅' : '❌'}"
  puts "   Thread name: #{thread&.name || 'N/A'}"
else
  puts '   ❌ Not found in supervisor'
end
puts ''

# Summary
puts '=' * 80
puts 'SUMMARY'
puts '=' * 80
puts ''

if all_ok && running
  puts '✅ All services are properly registered and can be started'
  puts '✅ Supervisor is running'
  puts ''
  puts 'If services are not working, check:'
  puts '  1. Are logs showing "[Supervisor] started <service>" messages?'
  puts '  2. Are there any errors in the logs?'
  puts '  3. Are threads actually running? (check Thread.list)'
  puts '  4. Is MarketFeedHub connected to WebSocket?'
  puts '  5. Are watchlist items being subscribed?'
else
  puts '❌ Some issues found:'
  puts "  - Supervisor running: #{running ? '✅' : '❌'}"
  puts "  - All services OK: #{all_ok ? '✅' : '❌'}"
  puts ''
  puts 'Check the errors above for details.'
end

puts ''
puts '=' * 80
