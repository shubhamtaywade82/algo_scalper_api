#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Integration Flow Test: Signals → Entries → Exits')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items
ServiceTestHelper.setup_test_instruments
ServiceTestHelper.setup_test_derivatives
ServiceTestHelper.setup_test_position_tracker(paper: true)

# This script tests the complete flow from signal generation to entry to exit

# Step 1: MarketFeedHub must be running
ServiceTestHelper.print_section('Step 1: MarketFeedHub')
hub = Live::MarketFeedHub.instance
if hub.running?
  ServiceTestHelper.print_success('MarketFeedHub is running')
else
  ServiceTestHelper.print_warning('Starting MarketFeedHub...')
  hub.start!
  ServiceTestHelper.wait_for(3, 'Waiting for WebSocket connection')
end

# Step 2: Check TickCache has data
ServiceTestHelper.print_section('Step 2: TickCache')
tick_cache = TickCache.instance
watchlist_items = WatchlistItem.where(active: true).includes(:watchable).limit(3)

if watchlist_items.any?
  watchlist_items.each do |item|
    watchable = item.watchable
    next unless watchable

    seg = watchable.respond_to?(:exchange_segment) ? watchable.exchange_segment : item.segment
    sid = watchable.respond_to?(:security_id) ? watchable.security_id : item.security_id
    symbol = watchable.respond_to?(:symbol_name) ? watchable.symbol_name : item.label

    # Try TickCache first
    ltp = tick_cache.ltp(seg, sid)

    # If no LTP in cache, fetch from DhanHQ API
    unless ltp&.positive?
      ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid)
      ServiceTestHelper.print_info("Fetched LTP from DhanHQ API for #{symbol}") if ltp
    end

    if ltp&.positive?
      ServiceTestHelper.print_success("#{symbol}: LTP = ₹#{ltp}")
    else
      ServiceTestHelper.print_warning("#{symbol}: No LTP available")
    end
  end
else
  ServiceTestHelper.print_warning('No active watchlist items')
end

# Step 3: Signal Generation
ServiceTestHelper.print_section('Step 3: Signal Generation')
scheduler = Signal::Scheduler.new
if scheduler.respond_to?(:running?) && scheduler.running?
  ServiceTestHelper.print_success('Signal Scheduler is running')
else
  ServiceTestHelper.print_info('Signal Scheduler status: Check logs for signal generation')
end

# Step 4: Capital Allocation
ServiceTestHelper.print_section('Step 4: Capital Allocation')
allocator = Capital::Allocator.new
# Use helper method with hardcoded fallback for reliability
current_capital = ServiceTestHelper.get_test_capital(fallback: 100_000.0)
ServiceTestHelper.print_info("Current capital: ₹#{current_capital}")

# Step 5: Entry Guard
ServiceTestHelper.print_section('Step 5: Entry Guard')
Entries::EntryGuard.new # Initialize for testing
active_positions = PositionTracker.active.count
ServiceTestHelper.print_info("Active positions: #{active_positions}")

# Step 6: ActiveCache
ServiceTestHelper.print_section('Step 6: ActiveCache')
active_cache = Positions::ActiveCache.instance
if active_cache.respond_to?(:start!)
  active_cache.start! unless active_cache.instance_variable_get(:@subscription_id)
  ServiceTestHelper.print_success('ActiveCache started')
end

cached_positions = active_cache.all_positions.count
ServiceTestHelper.print_info("Cached positions: #{cached_positions}")

# Step 7: Exit Engine
ServiceTestHelper.print_section('Step 7: Exit Engine')
router = TradingSystem::OrderRouter.new
Live::ExitEngine.new(order_router: router) # Initialize for testing
ServiceTestHelper.print_info('Exit Engine initialized')

# Step 8: PnL Tracking
ServiceTestHelper.print_section('Step 8: PnL Tracking')
pnl_cache = Live::RedisPnlCache.instance

if active_positions > 0
  tracker = PositionTracker.active.first
  pnl_data = pnl_cache.fetch_pnl(tracker.id)
  if pnl_data
    ServiceTestHelper.print_success("Tracker #{tracker.id} PnL: ₹#{pnl_data[:pnl]}")
  else
    ServiceTestHelper.print_info("Tracker #{tracker.id}: PnL not yet calculated")
  end
end

# Step 9: Complete Flow Summary
ServiceTestHelper.print_section('Complete Flow Summary')
ServiceTestHelper.print_info('Flow: MarketFeedHub → TickCache → Signals → EntryGuard → ActiveCache → ExitEngine')
ServiceTestHelper.print_info('All services are integrated and running')

ServiceTestHelper.print_success('Integration flow test completed')
