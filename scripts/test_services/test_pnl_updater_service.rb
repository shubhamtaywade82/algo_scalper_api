#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Live::PnlUpdaterService Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_position_tracker(paper: true)

pnl_updater = Live::PnlUpdaterService.instance

# Test 1: Check active positions
ServiceTestHelper.print_section('1. Active Positions Check')
active_positions = PositionTracker.active.includes(:watchable)
ServiceTestHelper.print_info("Found #{active_positions.count} active positions")

if active_positions.empty?
  ServiceTestHelper.print_warning('No active positions - creating test data')
  # We'll test with cache_intermediate_pnl instead
end

# Test 2: Cache intermediate PnL
ServiceTestHelper.print_section('2. Cache Intermediate PnL')
test_tracker_id = active_positions.first&.id || 999_999
test_pnl = 1500.50
test_pnl_pct = 5.25
test_ltp = 25_500.0
test_hwm = 2000.0

result = pnl_updater.cache_intermediate_pnl(
  tracker_id: test_tracker_id,
  pnl: test_pnl,
  pnl_pct: test_pnl_pct,
  ltp: test_ltp,
  hwm: test_hwm
)

ServiceTestHelper.check_condition(
  result,
  'Intermediate PnL cached successfully',
  'Failed to cache intermediate PnL'
)

# Test 3: Start PnL updater
ServiceTestHelper.print_section('3. Starting PnL Updater')
if pnl_updater.running?
  ServiceTestHelper.print_success('PnL Updater already running')
else
  pnl_updater.start!
  ServiceTestHelper.wait_for(1, 'Waiting for updater to start')
  ServiceTestHelper.check_condition(
    pnl_updater.running?,
    'PnL Updater started',
    'Failed to start PnL Updater'
  )
end

# Test 4: Wait for flush
ServiceTestHelper.print_section('4. Waiting for Flush')
ServiceTestHelper.print_info("Flush interval: #{Live::PnlUpdaterService::FLUSH_INTERVAL_SECONDS} seconds")
ServiceTestHelper.wait_for(Live::PnlUpdaterService::FLUSH_INTERVAL_SECONDS + 1, 'Waiting for flush')

# Test 5: Check Redis PnL cache
ServiceTestHelper.print_section('5. Redis PnL Cache Check')
if active_positions.any?
  tracker = active_positions.first
  pnl_data = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)

  if pnl_data
    ServiceTestHelper.print_success("Tracker #{tracker.id} PnL cached")
    ServiceTestHelper.print_info("PnL data:\n#{ServiceTestHelper.format_hash(pnl_data)}")
  else
    ServiceTestHelper.print_warning("Tracker #{tracker.id} PnL not yet cached")
  end
end

# Test 6: Verify updater thread
ServiceTestHelper.print_section('6. Updater Thread Check')
updater_thread = Thread.list.find { |t| t.name == 'pnl-updater-service' }
if updater_thread&.alive?
  ServiceTestHelper.print_success('Updater thread is running')
else
  ServiceTestHelper.print_warning('Updater thread not found or not running')
end

# Test 7: Test batch processing
ServiceTestHelper.print_section('7. Batch Processing Test')
ServiceTestHelper.print_info("Max batch size: #{Live::PnlUpdaterService::MAX_BATCH}")

# Cache multiple PnL values
active_positions.limit(5).each do |tracker|
  next unless tracker.entry_price.present? && tracker.quantity.present?

  seg = tracker.segment || tracker.watchable&.exchange_segment
  sid = tracker.security_id
  ltp = Live::TickCache.ltp(seg, sid) if seg && sid

  # If no LTP in cache, fetch from DhanHQ API
  ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s) if !ltp&.positive? && seg && sid

  next unless ltp&.positive?

  entry = tracker.entry_price.to_f
  qty = tracker.quantity.to_i
  pnl = (ltp - entry) * qty
  pnl_pct = entry.positive? ? ((ltp - entry) / entry * 100) : 0

  pnl_updater.cache_intermediate_pnl(
    tracker_id: tracker.id,
    pnl: pnl,
    pnl_pct: pnl_pct,
    ltp: ltp,
    hwm: tracker.high_water_mark_pnl&.to_f || pnl
  )
end

ServiceTestHelper.print_info("Cached PnL for #{active_positions.limit(5).count} trackers")
ServiceTestHelper.wait_for(Live::PnlUpdaterService::FLUSH_INTERVAL_SECONDS + 1, 'Waiting for batch flush')

# Test 8: Cleanup
ServiceTestHelper.print_section('8. Cleanup')
at_exit do
  pnl_updater.stop!
  ServiceTestHelper.print_info('PnL Updater stopped')
end

ServiceTestHelper.print_success('PnlUpdaterService test completed')
