#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick Health Check for All Services
# This script verifies that all services are properly initialized and can start
# Usage: rails runner scripts/health_check_all_services.rb

puts '=' * 80
puts 'SERVICE HEALTH CHECK'
puts '=' * 80
puts ''

# Check if supervisor exists
supervisor = Rails.application.config.x.trading_supervisor
unless supervisor
  puts '❌ ERROR: Supervisor not found'
  puts '   Make sure you are running this in a web server context (bin/dev or rails s)'
  exit 1
end

puts '✅ Supervisor found'
puts ''

# Get all registered services
services = supervisor.instance_variable_get(:@services) || {}
puts "Total services registered: #{services.size}"
puts ''

# Health check results
health_status = {
  healthy: [],
  warnings: [],
  unhealthy: []
}

services.each do |name, service|
  status = 'healthy'
  issues = []

  # Check 1: Service class exists
  unless service
    status = 'unhealthy'
    issues << 'Service instance is nil'
    health_status[:unhealthy] << { name: name, issues: issues }
    next
  end

  # Check 2: Has start method
  unless service.respond_to?(:start)
    status = 'unhealthy'
    issues << 'Missing start method'
  end

  # Check 3: Has stop method
  unless service.respond_to?(:stop)
    status = 'unhealthy'
    issues << 'Missing stop method'
  end

  # Check 4: Can instantiate (if needed)
  begin
    # Try to check if service can respond to basic methods
    service.class.name
  rescue StandardError => e
    status = 'unhealthy'
    issues << "Cannot access service class: #{e.message}"
  end

  # Check 5: Running status (if available)
  if service.respond_to?(:running?)
    begin
      running = service.running?
      issues << "Running: #{running ? 'YES' : 'NO'}" unless running
    rescue StandardError => e
      status = 'warnings'
      issues << "Cannot check running status: #{e.message}"
    end
  end

  # Categorize
  if status == 'unhealthy' || issues.any? { |i| i.include?('Missing') }
    health_status[:unhealthy] << { name: name, issues: issues }
  elsif status == 'warnings' || issues.any?
    health_status[:warnings] << { name: name, issues: issues }
  else
    health_status[:healthy] << { name: name }
  end
end

# Print results
puts '=' * 80
puts 'HEALTH CHECK RESULTS'
puts '=' * 80
puts ''

if health_status[:healthy].any?
  puts "✅ Healthy Services (#{health_status[:healthy].size}):"
  health_status[:healthy].each do |service|
    puts "   ✅ #{service[:name]}"
  end
  puts ''
end

if health_status[:warnings].any?
  puts "⚠️  Services with Warnings (#{health_status[:warnings].size}):"
  health_status[:warnings].each do |service|
    puts "   ⚠️  #{service[:name]}"
    service[:issues].each do |issue|
      puts "      - #{issue}"
    end
  end
  puts ''
end

if health_status[:unhealthy].any?
  puts "❌ Unhealthy Services (#{health_status[:unhealthy].size}):"
  health_status[:unhealthy].each do |service|
    puts "   ❌ #{service[:name]}"
    service[:issues].each do |issue|
      puts "      - #{issue}"
    end
  end
  puts ''
end

# Specific service checks
puts '=' * 80
puts 'DETAILED SERVICE CHECKS'
puts '=' * 80
puts ''

# 1. MarketFeedHub
puts '1. MarketFeedHub:'
begin
  hub = Live::MarketFeedHub.instance
  puts "   Class: ✅ #{hub.class.name}"
  puts "   Running: #{hub.running? ? '✅ YES' : '❌ NO'}"
  puts "   Connected: #{hub.connected? ? '✅ YES' : '❌ NO'}"
  watchlist = hub.instance_variable_get(:@watchlist) || []
  puts "   Watchlist: ✅ #{watchlist.count} instruments"
rescue StandardError => e
  puts "   ❌ ERROR: #{e.class} - #{e.message}"
end
puts ''

# 2. Signal::Scheduler
puts '2. Signal::Scheduler:'
begin
  scheduler = services[:signal_scheduler]
  if scheduler
    puts "   Class: ✅ #{scheduler.class.name}"
    running = scheduler.instance_variable_get(:@running)
    thread = scheduler.instance_variable_get(:@thread)
    puts "   Running: #{running ? '✅ YES' : '❌ NO'}"
    puts "   Thread: #{thread&.alive? ? '✅ ALIVE' : '❌ DEAD'}"
    puts "   Thread name: #{thread&.name || 'N/A'}"
  else
    puts "   ❌ Not found in supervisor"
  end
rescue StandardError => e
  puts "   ❌ ERROR: #{e.class} - #{e.message}"
end
puts ''

# 3. RiskManager
puts '3. RiskManager:'
begin
  risk = services[:risk_manager]
  if risk
    puts "   Class: ✅ #{risk.class.name}"
    puts "   Running: #{risk.running? ? '✅ YES' : '❌ NO'}"
    thread = risk.instance_variable_get(:@thread)
    puts "   Thread: #{thread&.alive? ? '✅ ALIVE' : '❌ DEAD'}"
    puts "   Thread name: #{thread&.name || 'N/A'}"
  else
    puts "   ❌ Not found in supervisor"
  end
rescue StandardError => e
  puts "   ❌ ERROR: #{e.class} - #{e.message}"
end
puts ''

# 4. ActiveCache
puts '4. ActiveCache:'
begin
  cache = Positions::ActiveCache.instance
  subscription_id = cache.instance_variable_get(:@subscription_id)
  puts "   Class: ✅ #{cache.class.name}"
  puts "   Subscribed: #{subscription_id ? '✅ YES' : '❌ NO'}"
  positions_count = cache.all_positions.count
  puts "   Active positions: ✅ #{positions_count}"
rescue StandardError => e
  puts "   ❌ ERROR: #{e.class} - #{e.message}"
end
puts ''

# 5. PositionHeartbeat
puts '5. PositionHeartbeat:'
begin
  heartbeat = services[:position_heartbeat]
  if heartbeat
    puts "   Class: ✅ #{heartbeat.class.name}"
    running = heartbeat.instance_variable_get(:@running)
    thread = heartbeat.instance_variable_get(:@thread)
    puts "   Running: #{running ? '✅ YES' : '❌ NO'}"
    puts "   Thread: #{thread&.alive? ? '✅ ALIVE' : '❌ DEAD'}"
    puts "   Thread name: #{thread&.name || 'N/A'}"
  else
    puts "   ❌ Not found in supervisor"
  end
rescue StandardError => e
  puts "   ❌ ERROR: #{e.class} - #{e.message}"
end
puts ''

# 6. PaperPnlRefresher
puts '6. PaperPnlRefresher:'
begin
  pnl = services[:paper_pnl_refresher]
  if pnl
    puts "   Class: ✅ #{pnl.class.name}"
    running = pnl.instance_variable_get(:@running)
    thread = pnl.instance_variable_get(:@thread)
    puts "   Running: #{running ? '✅ YES' : '❌ NO'}"
    puts "   Thread: #{thread&.alive? ? '✅ ALIVE' : '❌ DEAD'}"
    puts "   Thread name: #{thread&.name || 'N/A'}"
  else
    puts "   ❌ Not found in supervisor"
  end
rescue StandardError => e
  puts "   ❌ ERROR: #{e.class} - #{e.message}"
end
puts ''

# 7. ExitEngine
puts '7. ExitEngine:'
begin
  exit_engine = services[:exit_manager]
  if exit_engine
    puts "   Class: ✅ #{exit_engine.class.name}"
    running = exit_engine.instance_variable_get(:@running)
    thread = exit_engine.instance_variable_get(:@thread)
    puts "   Running: #{running ? '✅ YES' : '❌ NO'}"
    puts "   Thread: #{thread&.alive? ? '✅ ALIVE' : '❌ DEAD'}"
    puts "   Thread name: #{thread&.name || 'N/A'}"
  else
    puts "   ❌ Not found in supervisor"
  end
rescue StandardError => e
  puts "   ❌ ERROR: #{e.class} - #{e.message}"
end
puts ''

# Summary
puts '=' * 80
puts 'SUMMARY'
puts '=' * 80
puts ''

total = services.size
healthy = health_status[:healthy].size
warnings = health_status[:warnings].size
unhealthy = health_status[:unhealthy].size

puts "Total services: #{total}"
puts "✅ Healthy: #{healthy}"
puts "⚠️  Warnings: #{warnings}"
puts "❌ Unhealthy: #{unhealthy}"
puts ''

if unhealthy.zero? && warnings.zero?
  puts '🎉 All services are healthy!'
  exit 0
elsif unhealthy.zero?
  puts '⚠️  Some services have warnings, but all are functional'
  exit 0
else
  puts '❌ Some services are unhealthy. Check the details above.'
  puts ''
  puts 'Next steps:'
  puts '  1. Check logs: tail -f log/development.log'
  puts '  2. Run detailed tests: ./scripts/test_services/run_all_tests.sh'
  puts '  3. Check individual service: rails runner scripts/test_services/test_<service>.rb'
  exit 1
end

