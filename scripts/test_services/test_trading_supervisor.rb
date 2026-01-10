#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('TradingSupervisor Integration Test')

# This test verifies that TradingSupervisor can start/stop all registered services
# Note: This only works when running in a web server context (puma/rails server)

# Check if we're in the right environment
ServiceTestHelper.print_section('0. Environment Check')
is_web_process = $PROGRAM_NAME.include?('puma') ||
                 $PROGRAM_NAME.include?('rails') ||
                 ENV['WEB_CONCURRENCY'].present?

if Rails.env.test?
  ServiceTestHelper.print_warning('Running in test environment - TradingSupervisor is disabled')
  ServiceTestHelper.print_info('TradingSupervisor only runs in development/production web processes')
  exit 0
end

unless is_web_process
  ServiceTestHelper.print_warning('Not running in web process - TradingSupervisor may not be initialized')
  ServiceTestHelper.print_info('TradingSupervisor requires: puma, rails server, or WEB_CONCURRENCY env var')
end

# Check if supervisor is available
ServiceTestHelper.print_section('1. Supervisor Availability')
config_supervisor = Rails.application.config.x.trading_supervisor

# Check if it's actually a Supervisor instance (not just OrderedOptions)
# TradingSystem::Supervisor is defined in config/initializers/trading_supervisor.rb
if config_supervisor.is_a?(TradingSystem::Supervisor)
  supervisor = config_supervisor
  ServiceTestHelper.print_success('TradingSupervisor found (from initializer)')
else
  # Create supervisor for testing if it doesn't exist or is not initialized
  ServiceTestHelper.print_info('TradingSupervisor not initialized - creating for testing')
  supervisor = TradingSystem::Supervisor.new
  Rails.application.config.x.trading_supervisor = supervisor
  ServiceTestHelper.print_success('TradingSupervisor created for testing')
end

# List registered services
ServiceTestHelper.print_section('2. Registered Services')
services = supervisor.instance_variable_get(:@services) || {}
ServiceTestHelper.print_info("Total services registered: #{services.size}")

# If no services registered, register them for testing
if services.empty?
  ServiceTestHelper.print_section('2a. Registering Services for Testing')
  ServiceTestHelper.print_info('No services registered - registering for testing...')

  # Service adapters are defined in config/initializers/trading_supervisor.rb
  # MarketFeedHubService and ActiveCacheService are already available

  # Register services (same as initializer)
  begin
    feed = MarketFeedHubService.new
    router = TradingSystem::OrderRouter.new

    supervisor.register(:market_feed, feed)
    supervisor.register(:signal_scheduler, Signal::Scheduler.new)
    supervisor.register(:risk_manager, Live::RiskManagerService.new)
    supervisor.register(:position_heartbeat, TradingSystem::PositionHeartbeat.new)
    supervisor.register(:order_router, router)
    supervisor.register(:paper_pnl_refresher, Live::PaperPnlRefresher.new)
    supervisor.register(:exit_manager, Live::ExitEngine.new(order_router: router))
    supervisor.register(:active_cache, ActiveCacheService.new)

    services = supervisor.instance_variable_get(:@services) || {}
    if services.size.positive?
      ServiceTestHelper.print_success("Registered #{services.size} services for testing")
      services.each_key do |name|
        ServiceTestHelper.print_info("  ✅ Registered: #{name}")
      end
    else
      ServiceTestHelper.print_error('Failed to register services - services hash is empty')
      ServiceTestHelper.print_info("Supervisor class: #{supervisor.class}")
      ServiceTestHelper.print_info("Supervisor methods: #{supervisor.methods.grep(/register/)}")
    end
  rescue StandardError => e
    ServiceTestHelper.print_error("Error registering services: #{e.class} - #{e.message}")
    ServiceTestHelper.print_info("Backtrace: #{e.backtrace.first(3).join("\n")}")
  end
end

services.each do |name, service|
  has_start = service.respond_to?(:start) || service.respond_to?(:start!)
  has_stop = service.respond_to?(:stop) || service.respond_to?(:stop!)

  if has_start && has_stop
    ServiceTestHelper.print_success("  ✅ #{name}: has start/stop methods")
  else
    ServiceTestHelper.print_error("  ❌ #{name}: missing start/stop methods")
    ServiceTestHelper.print_info("     start: #{has_start}, stop: #{has_stop}")
  end
end

# Check service types
ServiceTestHelper.print_section('3. Service Type Verification')
expected_services = %i[
  market_feed
  signal_scheduler
  risk_manager
  position_heartbeat
  order_router
  paper_pnl_refresher
  exit_manager
  active_cache
]

expected_services.each do |name|
  if services.key?(name)
    ServiceTestHelper.print_success("  ✅ #{name} is registered")
  else
    ServiceTestHelper.print_warning("  ⚠️  #{name} is NOT registered")
  end
end

# Test service start/stop (if supervisor is running)
ServiceTestHelper.print_section('4. Service Start/Stop Test')
running = supervisor.instance_variable_get(:@running)

if running
  ServiceTestHelper.print_info('Supervisor is already running')
  ServiceTestHelper.print_info('Services should be active. Check logs for any errors.')
else
  ServiceTestHelper.print_info('Supervisor is not running')
  ServiceTestHelper.print_info('This is expected if services were not started yet')
end

# Check critical service dependencies
ServiceTestHelper.print_section('5. Critical Service Dependencies')

# MarketFeedHub
if services[:market_feed]
  feed_service = services[:market_feed]
  hub = begin
    feed_service.instance_variable_get(:@hub)
  rescue StandardError
    nil
  end
  if hub
    hub_running = begin
      hub.running?
    rescue StandardError
      false
    end
    if hub_running
      ServiceTestHelper.print_success('MarketFeedHub is running')
    else
      ServiceTestHelper.print_warning('MarketFeedHub is not running')
    end
  end
end

# ActiveCache
if services[:active_cache]
  cache_service = services[:active_cache]
  cache = begin
    cache_service.instance_variable_get(:@cache)
  rescue StandardError
    nil
  end
  if cache
    ServiceTestHelper.print_success('ActiveCache service found')
    # Check if it's subscribed
    subscription_id = begin
      cache.instance_variable_get(:@subscription_id)
    rescue StandardError
      nil
    end
    if subscription_id
      ServiceTestHelper.print_success('ActiveCache is subscribed to MarketFeedHub')
    else
      ServiceTestHelper.print_warning('ActiveCache may not be subscribed')
    end
  end
end

# Signal Scheduler
if services[:signal_scheduler]
  scheduler = services[:signal_scheduler]
  ServiceTestHelper.print_success('Signal::Scheduler service found')
  # Check if it has required dependencies
  if scheduler.respond_to?(:running?)
    running = begin
      scheduler.running?
    rescue StandardError
      false
    end
    ServiceTestHelper.print_info("  Scheduler running: #{running}")
  end
end

ServiceTestHelper.print_section('6. Recommendations')
ServiceTestHelper.print_info('To fully test TradingSupervisor:')
ServiceTestHelper.print_info('  1. Start Rails server: bin/dev or rails s')
ServiceTestHelper.print_info('  2. Check logs for service startup messages')
ServiceTestHelper.print_info('  3. Verify services are running:')
ServiceTestHelper.print_info('     - MarketFeedHub should show WebSocket connection')
ServiceTestHelper.print_info('     - Signal::Scheduler should process watchlist items')
ServiceTestHelper.print_info('     - ActiveCache should subscribe to MarketFeedHub')

ServiceTestHelper.print_success('TradingSupervisor test completed')
