# frozen_string_literal: true

# Service Testing Runner for Rails Console
# Usage: Load this file in Rails console and use the helper methods
#
# Example:
#   load 'lib/testing/service_test_runner.rb'
#   test_market_feed_hub
#   test_risk_manager_service

module ServiceTestRunner
  extend self

  # Colors for console output
  COLORS = {
    reset: "\e[0m",
    bold: "\e[1m",
    green: "\e[32m",
    yellow: "\e[33m",
    red: "\e[31m",
    blue: "\e[34m",
    cyan: "\e[36m"
  }.freeze

  def colorize(text, color)
    "#{COLORS[color]}#{text}#{COLORS[:reset]}"
  end

  def print_header(title)
    puts "\n#{colorize('=' * 80, :bold)}"
    puts colorize("  #{title}", :bold)
    puts colorize('=' * 80, :reset)
  end

  def print_section(title)
    puts "\n#{colorize("▶ #{title}", :cyan)}"
  end

  def print_success(message)
    puts "#{colorize('✓', :green)} #{message}"
  end

  def print_error(message)
    puts "#{colorize('✗', :red)} #{message}"
  end

  def print_warning(message)
    puts "#{colorize('⚠', :yellow)} #{message}"
  end

  def print_info(message)
    puts "#{colorize('ℹ', :blue)} #{message}"
  end

  def wait_for_logs(seconds = 5)
    print_info("Observing logs for #{seconds} seconds...")
    sleep(seconds)
  end

  def check_service_status(service_name, running_method = :running?)
    service = Object.const_get(service_name)
    if service.respond_to?(:instance)
      instance = service.instance
      status = instance.respond_to?(running_method) ? instance.public_send(running_method) : 'N/A'
      print_info("#{service_name}: #{status ? colorize('RUNNING', :green) : colorize('STOPPED', :red)}")
      status
    else
      print_warning("#{service_name} is not a singleton - check manually")
      false
    end
  rescue NameError => e
    print_error("#{service_name} not found: #{e.message}")
    false
  end

  # ============================================================================
  # INDEPENDENT SERVICES (Singleton/Threaded)
  # ============================================================================

  def test_market_feed_hub
    print_header('Testing MarketFeedHub')
    service = Live::MarketFeedHub.instance

    print_section('Initial Status')
    print_info("Running: #{service.running?}")
    print_info("Connected: #{service.connected?}")

    print_section('Starting Service')
    if service.running?
      print_warning('Service already running - stopping first')
      service.stop!
      sleep(2)
    end

    print_info('Starting MarketFeedHub...')
    service.start!
    sleep(3)

    print_section('Post-Start Status')
    print_info("Running: #{service.running?}")
    print_info("Connected: #{service.connected?}")
    print_info("Subscribed instruments: #{service.subscribed_instruments.count}")

    print_section('Observing Logs')
    wait_for_logs(10)

    print_section('Testing Tick Subscription')
    # Try subscribing to a test instrument if available
    nifty = Instrument.find_by(symbol: 'NIFTY')
    if nifty
      print_info("Subscribing to NIFTY: #{nifty.security_id}")
      service.subscribe_instrument(segment: nifty.segment, security_id: nifty.security_id)
      wait_for_logs(5)
    else
      print_warning('NIFTY instrument not found in database')
    end

    print_section('Final Status')
    print_info("Running: #{service.running?}")
    print_info("Connected: #{service.connected?}")

    print_success('MarketFeedHub test completed')
    service
  end

  def test_risk_manager_service
    print_header('Testing RiskManagerService')

    # Get instance from supervisor or create test instance
    print_section('Initializing Service')
    order_router = TradingSystem::OrderRouter.instance
    exit_engine = Live::ExitEngine.new(order_router: order_router)
    trailing_engine = Live::TrailingEngine.new
    # RuleEngine is created via factory - RiskManagerService will create it if nil
    rule_engine = Risk::Rules::RuleFactory.create_engine(risk_config: {}) rescue nil

    service = Live::RiskManagerService.new(
      exit_engine: exit_engine,
      trailing_engine: trailing_engine,
      rule_engine: rule_engine
    )

    print_section('Pre-Start Status')
    print_info("Running: #{service.running?}")
    print_info("Active positions: #{PositionTracker.active.count}")

    print_section('Starting Service')
    service.start
    sleep(2)

    print_section('Post-Start Status')
    print_info("Running: #{service.running?}")
    print_info("Thread alive: #{service.instance_variable_get(:@thread)&.alive?}")

    print_section('Observing Monitoring Loop')
    wait_for_logs(15)

    print_section('Checking Active Positions')
    active = PositionTracker.active.limit(5)
    if active.any?
      print_info("Found #{active.count} active positions")
      active.each do |tracker|
        print_info("  - Tracker #{tracker.id}: #{tracker.instrument&.symbol} | PnL: #{tracker.last_pnl_rupees}")
      end
    else
      print_info('No active positions found')
    end

    print_section('Testing PnL Update')
    if active.any?
      tracker = active.first
      print_info("Updating PnL for tracker #{tracker.id}")
      service.update_pnl(tracker_id: tracker.id, pnl: 100.0)
      wait_for_logs(3)
    end

    print_section('Final Status')
    print_info("Running: #{service.running?}")
    print_info("Circuit breaker state: #{service.instance_variable_get(:@circuit_breaker_state)}")

    print_success('RiskManagerService test completed')
    service
  end

  def test_pnl_updater_service
    print_header('Testing PnlUpdaterService')
    service = Live::PnlUpdaterService.instance

    print_section('Initial Status')
    print_info("Running: #{service.running?}")

    print_section('Starting Service')
    if service.running?
      print_warning('Service already running')
    else
      service.start!
      sleep(2)
    end

    print_section('Post-Start Status')
    print_info("Running: #{service.running?}")

    print_section('Testing PnL Update Queue')
    active = PositionTracker.active.limit(3)
    if active.any?
      print_info("Queueing PnL updates for #{active.count} positions")
      active.each do |tracker|
        service.queue_update(tracker_id: tracker.id, pnl: rand(-100.0..100.0))
      end
      wait_for_logs(5)
    else
      print_info('No active positions - creating test update')
      service.queue_update(tracker_id: 999, pnl: 50.0)
      wait_for_logs(3)
    end

    print_section('Final Status')
    print_info("Running: #{service.running?}")

    print_success('PnlUpdaterService test completed')
    service
  end

  def test_paper_pnl_refresher
    print_header('Testing PaperPnlRefresher')

    # Create instance (not singleton)
    service = Live::PaperPnlRefresher.new

    print_section('Pre-Start Status')
    print_info("Running: #{service.running?}")
    paper_count = PositionTracker.active.where(paper: true).count
    print_info("Paper positions: #{paper_count}")

    print_section('Starting Service')
    service.start
    sleep(2)

    print_section('Post-Start Status')
    print_info("Running: #{service.running?}")

    print_section('Observing Refresh Loop')
    wait_for_logs(10)

    print_section('Manual Refresh Test')
    if paper_count > 0
      tracker = PositionTracker.active.where(paper: true).first
      print_info("Manually refreshing tracker #{tracker.id}")
      service.refresh_tracker(tracker)
      wait_for_logs(2)
    end

    print_section('Final Status')
    print_info("Running: #{service.running?}")

    print_success('PaperPnlRefresher test completed')
    service
  end

  def test_exit_engine
    print_header('Testing ExitEngine')

    # ExitEngine is not a singleton - create instance with order router
    print_section('Creating ExitEngine Instance')
    order_router = TradingSystem::OrderRouter.instance
    service = Live::ExitEngine.new(order_router: order_router)

    print_section('Initial Status')
    print_info("Running: #{service.running?}")

    print_section('Starting Service')
    service.start
    sleep(1)

    print_section('Post-Start Status')
    print_info("Running: #{service.running?}")

    print_section('Testing Exit Methods')
    active = PositionTracker.active.limit(1)
    if active.any?
      tracker = active.first
      print_info("Testing exit for tracker #{tracker.id}")
      print_warning('⚠️  This will attempt to exit a real position!')
      print_info('Skipping actual exit - check methods available:')
      print_info("  - execute_exit(tracker, reason: 'test')")
    else
      print_info('No active positions - service ready for exits')
    end

    print_success('ExitEngine test completed')
    service
  end

  def test_trailing_engine
    print_header('Testing TrailingEngine')

    # TrailingEngine is not a singleton - create instance
    print_section('Creating TrailingEngine Instance')
    service = Live::TrailingEngine.new

    print_section('Testing Trailing Logic')
    active = PositionTracker.active.limit(3)
    if active.any?
      print_info("Testing trailing for #{active.count} positions")
      active.each do |tracker|
        position_data = Positions::ActiveCache.instance.get(tracker_id: tracker.id)
        if position_data
          print_info("  Tracker #{tracker.id}: Peak=#{position_data.peak_profit_pct}%, " \
                     "Current=#{position_data.pnl_pct}%, SL=#{position_data.trailing_stop_price}")
        else
          print_info("  Tracker #{tracker.id}: Not in ActiveCache")
        end
      end
    else
      print_info('No active positions')
    end

    print_success('TrailingEngine test completed')
    service
  end

  # ============================================================================
  # SIGNAL SERVICES
  # ============================================================================

  def test_signal_scheduler
    print_header('Testing Signal::Scheduler')

    print_section('Creating Scheduler Instance')
    scheduler = Signal::Scheduler.new

    print_section('Pre-Start Status')
    print_info("Running: #{scheduler.running?}")

    print_section('Starting Service')
    scheduler.start
    sleep(3)

    print_section('Post-Start Status')
    print_info("Running: #{scheduler.running?}")

    print_section('Observing Signal Generation')
    wait_for_logs(30)

    print_section('Testing Manual Signal Processing')
    indices = ['NIFTY', 'BANKNIFTY']
    indices.each do |index_key|
      index_cfg = AlgoConfig.fetch('indices', index_key)
      if index_cfg
        print_info("Processing #{index_key}...")
        # scheduler.process_index(index_cfg) # Uncomment to test
        print_info("  Config: #{index_cfg.inspect}")
      end
    end

    print_success('Signal::Scheduler test completed')
    scheduler
  end

  # ============================================================================
  # UTILITY SERVICES (Stateless)
  # ============================================================================

  def test_tick_cache
    print_header('Testing TickCache')
    cache = Live::TickCache.instance

    print_section('Cache Status')
    print_info("Cache size: #{cache.size}")
    print_info("Keys: #{cache.keys.first(5).join(', ')}")

    print_section('Testing Lookup')
    nifty = Instrument.find_by(symbol: 'NIFTY')
    if nifty
      tick = cache.get(segment: nifty.segment, security_id: nifty.security_id)
      if tick
        print_success("Found tick for NIFTY: LTP=#{tick[:ltp]}")
      else
        print_warning('No tick found for NIFTY')
      end
    end

    print_section('Testing All Ticks')
    all_ticks = cache.all
    print_info("Total ticks in cache: #{all_ticks.count}")
    all_ticks.first(3).each do |key, tick|
      print_info("  #{key}: LTP=#{tick[:ltp]}")
    end

    print_success('TickCache test completed')
    cache
  end

  def test_redis_pnl_cache
    print_header('Testing RedisPnlCache')
    cache = Live::RedisPnlCache.instance

    print_section('Testing PnL Storage')
    test_tracker_id = 999
    test_pnl = 123.45
    cache.set(tracker_id: test_tracker_id, pnl: test_pnl)
    retrieved = cache.get(tracker_id: test_tracker_id)

    if retrieved == test_pnl
      print_success("PnL storage works: #{retrieved}")
    else
      print_error("PnL storage failed: expected #{test_pnl}, got #{retrieved}")
    end

    print_section('Testing Batch Operations')
    active = PositionTracker.active.limit(5)
    if active.any?
      pnl_data = active.map { |t| { tracker_id: t.id, pnl: t.last_pnl_rupees || 0.0 } }
      cache.set_batch(pnl_data)
      print_info("Set PnL for #{pnl_data.count} positions")

      retrieved_batch = cache.get_batch(tracker_ids: active.pluck(:id))
      print_info("Retrieved PnL for #{retrieved_batch.count} positions")
    end

    print_success('RedisPnlCache test completed')
    cache
  end

  def test_active_cache
    print_header('Testing ActiveCache')
    cache = Positions::ActiveCache.instance

    print_section('Cache Status')
    print_info("Empty: #{cache.empty?}")
    print_info("Size: #{cache.size}")

    print_section('Loading Active Positions')
    cache.bulk_load!
    print_info("Size after bulk_load: #{cache.size}")

    print_section('Testing Lookup')
    active = PositionTracker.active.limit(3)
    if active.any?
      active.each do |tracker|
        cached = cache.get(tracker_id: tracker.id)
        if cached
          print_success("Tracker #{tracker.id} found in cache")
        else
          print_warning("Tracker #{tracker.id} not in cache")
        end
      end
    end

    print_section('Testing All Positions')
    all = cache.all
    print_info("Total positions in cache: #{all.count}")
    all.first(3).each do |tracker_id, data|
      print_info("  Tracker #{tracker_id}: #{data[:instrument_symbol]}")
    end

    print_success('ActiveCache test completed')
    cache
  end

  def test_underlying_monitor
    print_header('Testing UnderlyingMonitor')
    monitor = Live::UnderlyingMonitor.instance

    print_section('Testing Health Check')
    nifty = Instrument.find_by(symbol: 'NIFTY')
    if nifty
      health = monitor.check_health(index_key: 'NIFTY')
      print_info("NIFTY health: #{health.inspect}")
    end

    print_section('Testing Structure Break Check')
    indices = ['NIFTY', 'BANKNIFTY']
    indices.each do |index_key|
      broken = monitor.structure_broken?(index_key: index_key)
      print_info("#{index_key} structure broken: #{broken}")
    end

    print_success('UnderlyingMonitor test completed')
    monitor
  end

  # ============================================================================
  # ORDER SERVICES
  # ============================================================================

  def test_order_router
    print_header('Testing OrderRouter')
    router = TradingSystem::OrderRouter.instance

    print_section('Initial Status')
    print_info("Running: #{router.running?}")

    print_section('Starting Service')
    router.start
    sleep(1)

    print_section('Post-Start Status')
    print_info("Running: #{router.running?}")

    print_section('Testing Route Methods')
    print_info('Available methods:')
    print_info('  - route_order(order_params)')
    print_info('  - route_bracket_order(bracket_params)')
    print_info('  - route_exit_order(tracker_id, reason)')

    print_success('OrderRouter test completed')
    router
  end

  # ============================================================================
  # COMPREHENSIVE TEST SUITE
  # ============================================================================

  def test_all_services
    print_header('COMPREHENSIVE SERVICE TEST SUITE')

    results = {}

    services_to_test = [
      { name: 'TickCache', method: :test_tick_cache },
      { name: 'ActiveCache', method: :test_active_cache },
      { name: 'RedisPnlCache', method: :test_redis_pnl_cache },
      { name: 'MarketFeedHub', method: :test_market_feed_hub },
      { name: 'OrderRouter', method: :test_order_router },
      { name: 'ExitEngine', method: :test_exit_engine },
      { name: 'TrailingEngine', method: :test_trailing_engine },
      { name: 'UnderlyingMonitor', method: :test_underlying_monitor },
      { name: 'PnlUpdaterService', method: :test_pnl_updater_service },
      { name: 'PaperPnlRefresher', method: :test_paper_pnl_refresher },
      { name: 'RiskManagerService', method: :test_risk_manager_service },
      { name: 'Signal::Scheduler', method: :test_signal_scheduler }
    ]

    services_to_test.each do |service|
      begin
        print_info("\n#{'=' * 80}")
        print_info("Testing #{service[:name]}")
        print_info('=' * 80)

        result = public_send(service[:method])
        results[service[:name]] = { status: :success, result: result }
        sleep(2) # Brief pause between services
      rescue StandardError => e
        print_error("#{service[:name]} failed: #{e.class} - #{e.message}")
        results[service[:name]] = { status: :error, error: e.message }
      end
    end

    print_header('TEST RESULTS SUMMARY')
    results.each do |name, result|
      if result[:status] == :success
        print_success("#{name}: PASSED")
      else
        print_error("#{name}: FAILED - #{result[:error]}")
      end
    end

    results
  end

  # ============================================================================
  # HELPER METHODS
  # ============================================================================

  def show_service_status
    print_header('Service Status Overview')

    services = [
      'Live::MarketFeedHub',
      'Live::RiskManagerService',
      'Live::PnlUpdaterService',
      'Live::ExitEngine',
      'Live::TrailingEngine',
      'TradingSystem::OrderRouter'
    ]

    services.each do |service_name|
      check_service_status(service_name)
    end
  end

  def show_active_positions
    print_header('Active Positions')

    active = PositionTracker.active.includes(:instrument)
    print_info("Total active positions: #{active.count}")

    active.limit(10).each do |tracker|
      print_info("  ID: #{tracker.id} | #{tracker.instrument&.symbol} | " \
                 "PnL: #{tracker.last_pnl_rupees} | Paper: #{tracker.paper}")
    end
  end

  def monitor_logs(seconds = 30)
    print_header("Monitoring Logs for #{seconds} seconds")
    print_info('Watch for service activity, errors, and status updates...')
    wait_for_logs(seconds)
    print_success('Log monitoring completed')
  end
end

# Make methods available in console
include ServiceTestRunner

puts "\n#{ServiceTestRunner.colorize('=' * 80, :bold)}"
puts ServiceTestRunner.colorize('  Service Test Runner Loaded', :bold)
puts ServiceTestRunner.colorize('=' * 80, :reset)
puts "\nAvailable test methods:"
puts "  - test_market_feed_hub"
puts "  - test_risk_manager_service"
puts "  - test_pnl_updater_service"
puts "  - test_paper_pnl_refresher"
puts "  - test_exit_engine"
puts "  - test_trailing_engine"
puts "  - test_signal_scheduler"
puts "  - test_tick_cache"
puts "  - test_redis_pnl_cache"
puts "  - test_active_cache"
puts "  - test_underlying_monitor"
puts "  - test_order_router"
puts "  - test_all_services (runs all tests)"
puts "\nHelper methods:"
puts "  - show_service_status"
puts "  - show_active_positions"
puts "  - monitor_logs(seconds)"
puts "\n"

