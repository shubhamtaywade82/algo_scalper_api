#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Live::PaperPnlRefresher Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_position_tracker(paper: true)

refresher = Live::PaperPnlRefresher.new

# Test 1: Check paper positions
ServiceTestHelper.print_section('1. Paper Positions Check')
paper_positions = PositionTracker.paper.active
ServiceTestHelper.print_info("Found #{paper_positions.count} active paper positions")

if paper_positions.empty?
  ServiceTestHelper.print_warning('No active paper positions - cannot test PnL refresh')
  ServiceTestHelper.print_info('Paper positions are created when trading in paper mode')
  exit 0
end

# Test 2: Start refresher
ServiceTestHelper.print_section('2. Starting PaperPnlRefresher')
refresher.start
ServiceTestHelper.print_success('PaperPnlRefresher started')
ServiceTestHelper.print_info("Refresh interval: #{Live::PaperPnlRefresher::REFRESH_INTERVAL} seconds")

# Test 3: Check initial PnL
ServiceTestHelper.print_section('3. Initial PnL Check')
paper_positions.limit(3).each do |tracker|
  ServiceTestHelper.print_info("\nTracker ID: #{tracker.id}")
  ServiceTestHelper.print_info("  Symbol: #{tracker.symbol}")
  ServiceTestHelper.print_info("  Entry Price: ₹#{tracker.entry_price}")
  ServiceTestHelper.print_info("  Quantity: #{tracker.quantity}")
  ServiceTestHelper.print_info("  Current PnL: ₹#{tracker.last_pnl_rupees || 0}")
  ServiceTestHelper.print_info("  PnL %: #{tracker.last_pnl_pct || 0}%")
  ServiceTestHelper.print_info("  HWM: ₹#{tracker.high_water_mark_pnl || 0}")
end

# Test 4: Wait for refresh cycle (limited wait to avoid timeout)
ServiceTestHelper.print_section('4. Waiting for Refresh Cycle')
refresh_interval = Live::PaperPnlRefresher::REFRESH_INTERVAL
# Limit wait to 30 seconds to avoid timeout (refresh interval is 40s)
wait_time = [refresh_interval + 5, 30].min
ServiceTestHelper.print_info("Refresh interval: #{refresh_interval}s, waiting: #{wait_time}s (limited for test)")
ServiceTestHelper.wait_for(wait_time, 'Waiting for PnL refresh')

# Test 5: Check updated PnL
ServiceTestHelper.print_section('5. Updated PnL Check')
paper_positions.limit(3).each do |tracker|
  tracker.reload
  ServiceTestHelper.print_info("\nTracker ID: #{tracker.id}")
  ServiceTestHelper.print_info("  Updated PnL: ₹#{tracker.last_pnl_rupees || 0}")
  ServiceTestHelper.print_info("  Updated PnL %: #{tracker.last_pnl_pct || 0}%")
  ServiceTestHelper.print_info("  Updated HWM: ₹#{tracker.high_water_mark_pnl || 0}")

  # Check Redis PnL cache
  pnl_data = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
  if pnl_data
    ServiceTestHelper.print_success("  Redis PnL: ₹#{pnl_data[:pnl]}")
  else
    ServiceTestHelper.print_warning('  Redis PnL: Not cached yet')
  end
end

# Test 6: Verify refresher thread
ServiceTestHelper.print_section('6. Refresher Thread Check')
refresher_thread = Thread.list.find { |t| t.name == 'paper-pnl-refresher' }
if refresher_thread&.alive?
  ServiceTestHelper.print_success('Refresher thread is running')
else
  ServiceTestHelper.print_warning('Refresher thread not found or not running')
end

# Test 7: Cleanup
ServiceTestHelper.print_section('7. Cleanup')
at_exit do
  refresher.stop
  ServiceTestHelper.print_info('PaperPnlRefresher stopped')
end

ServiceTestHelper.print_success('PaperPnlRefresher test completed')
ServiceTestHelper.print_info('Refresher runs continuously - check logs for refresh details')
