#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Positions::ActiveCache Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_derivatives

# Ensure we have a derivative position (not underlying index)
if PositionTracker.active.where(watchable_type: 'Derivative').empty?
  # Find ATM or 2 OTM derivative
  derivative = ServiceTestHelper.find_atm_or_otm_derivative(
    underlying_symbol: 'NIFTY',
    option_type: 'CE',
    preference: :atm
  ) || ServiceTestHelper.find_atm_or_otm_derivative(
    underlying_symbol: 'NIFTY',
    option_type: 'CE',
    preference: :atm_plus_2
  )

  if derivative
    seg = derivative.exchange_segment || 'NSE_FNO'
    sid = derivative.security_id
    ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s, suppress_rate_limit_warning: true) || 150.0

    tracker = ServiceTestHelper.create_position_tracker(
      watchable: derivative,
      order_no: "TEST-CACHE-#{Time.current.to_i}",
      security_id: sid.to_s,
      symbol: derivative.symbol_name || "NIFTY-#{derivative.strike_price}-CE",
      segment: seg,
      side: 'long_ce',
      quantity: 75,
      entry_price: ltp,
      paper: true
    )

    ServiceTestHelper.print_success("Created derivative position for ActiveCache test: #{tracker&.symbol}") if tracker
  end
end

ServiceTestHelper.setup_test_position_tracker(paper: true)  # Keep for backward compatibility

active_cache = Positions::ActiveCache.instance

# Test 1: Start ActiveCache
ServiceTestHelper.print_section('1. Starting ActiveCache')
if active_cache.start!
  ServiceTestHelper.print_success('ActiveCache started')
else
  ServiceTestHelper.print_error('Failed to start ActiveCache')
  exit 1
end

# Test 2: Check active positions
ServiceTestHelper.print_section('2. Active Positions')
active_positions = PositionTracker.active.includes(:watchable)
ServiceTestHelper.print_info("Found #{active_positions.count} active positions")

# Test 3: Add positions to cache
ServiceTestHelper.print_section('3. Adding Positions to Cache')
if active_positions.any?
  added_count = 0
  active_positions.limit(3).each do |tracker|
    # Calculate SL/TP
    entry = tracker.entry_price.to_f
    sl_price = entry * 0.70  # 30% below
    tp_price = entry * 1.60  # 60% above

    position_data = active_cache.add_position(
      tracker: tracker,
      sl_price: sl_price,
      tp_price: tp_price
    )

    if position_data
      ServiceTestHelper.print_success("Added tracker #{tracker.id} to cache")
      ServiceTestHelper.print_info("  Entry: ₹#{position_data.entry_price}")
      ServiceTestHelper.print_info("  SL: ₹#{position_data.sl_price}")
      ServiceTestHelper.print_info("  TP: ₹#{position_data.tp_price}")
      added_count += 1
    else
      ServiceTestHelper.print_warning("Failed to add tracker #{tracker.id}")
    end
  end
  ServiceTestHelper.print_info("Added #{added_count} positions to cache")
else
  ServiceTestHelper.print_info('No active positions to add (this is expected if no trades are running)')
end

# Test 4: Get cached positions
ServiceTestHelper.print_section('4. Cached Positions')
all_cached = active_cache.all_positions
ServiceTestHelper.print_info("Total cached positions: #{all_cached.size}")

if all_cached.any?
  all_cached.each do |position|
    ServiceTestHelper.print_info("\nTracker ID: #{position.tracker_id}")
    ServiceTestHelper.print_info("  Composite Key: #{position.composite_key}")
    ServiceTestHelper.print_info("  Current LTP: ₹#{position.current_ltp || 'N/A'}")
    ServiceTestHelper.print_info("  PnL: ₹#{position.pnl || 0}")
    ServiceTestHelper.print_info("  PnL %: #{position.pnl_pct || 0}%")
    ServiceTestHelper.print_info("  HWM: ₹#{position.high_water_mark || 0}")
    ServiceTestHelper.print_info("  SL Hit: #{position.sl_hit?}")
    ServiceTestHelper.print_info("  TP Hit: #{position.tp_hit?}")
  end
end

# Test 5: Update position LTP (try real API first)
ServiceTestHelper.print_section('5. Update Position LTP')
if all_cached.any?
  # Update all positions with real LTP from API
  all_cached.each do |position|
    segment, security_id = position.composite_key.split(':')

    # Try to fetch real LTP from DhanHQ API
    real_ltp = ServiceTestHelper.fetch_ltp(segment: segment, security_id: security_id, suppress_rate_limit_warning: true)

    if real_ltp
      position.update_ltp(real_ltp)
      ServiceTestHelper.print_success("Tracker #{position.tracker_id}: Updated LTP to ₹#{real_ltp} (API)")
      ServiceTestHelper.print_info("  PnL: ₹#{position.pnl.round(2)}")
      ServiceTestHelper.print_info("  PnL %: #{position.pnl_pct.round(2)}%")
    else
      # Use fallback for testing
      fallback_ltp = position.entry_price * 1.01  # 1% above entry
      position.update_ltp(fallback_ltp)
      ServiceTestHelper.print_info("Tracker #{position.tracker_id}: Using fallback LTP ₹#{fallback_ltp.round(2)}")
    end
  end
end

# Test 6: Check SL/TP hits
ServiceTestHelper.print_section('6. SL/TP Hit Detection')
if all_cached.any?
  all_cached.each do |position|
    if position.sl_hit?
      ServiceTestHelper.print_warning("Tracker #{position.tracker_id}: SL HIT!")
    elsif position.tp_hit?
      ServiceTestHelper.print_success("Tracker #{position.tracker_id}: TP HIT!")
    end
  end
end

# Test 7: Bulk load
ServiceTestHelper.print_section('7. Bulk Load')
active_cache.clear
count = active_cache.bulk_load!
ServiceTestHelper.print_success("Bulk loaded #{count} positions")

# Test 8: Wait for real-time tick updates
ServiceTestHelper.print_section('8. Real-Time Tick Updates')
ServiceTestHelper.print_info('ActiveCache is subscribed to MarketFeedHub callbacks')
ServiceTestHelper.print_info('Waiting for ticks to arrive (if MarketFeedHub is running)...')
ServiceTestHelper.wait_for(3, 'Waiting for tick updates')

# Check if any ticks were processed
stats_before = active_cache.stats.dup
ServiceTestHelper.print_info("Updates processed: #{stats_before[:updates_processed]}")

# If MarketFeedHub is running, we should see updates
hub = Live::MarketFeedHub.instance
if hub.running? && hub.connected?
  ServiceTestHelper.print_success('MarketFeedHub is running and connected')
  ServiceTestHelper.print_info('Ticks should be arriving - check updates_processed count')
else
  ServiceTestHelper.print_warning('MarketFeedHub is not running or not connected')
  ServiceTestHelper.print_info('ActiveCache will receive ticks when MarketFeedHub starts')
end

# Test 9: Statistics
ServiceTestHelper.print_section('9. Statistics')
stats = active_cache.stats
ServiceTestHelper.print_info("Cache stats:\n#{ServiceTestHelper.format_hash(stats)}")

# Show final position states
if all_cached.any?
  ServiceTestHelper.print_info("\nFinal Position States:")
  all_cached.each do |position|
    ServiceTestHelper.print_info("  Tracker #{position.tracker_id}:")
    ServiceTestHelper.print_info("    LTP: ₹#{position.current_ltp || 'N/A'}")
    ServiceTestHelper.print_info("    PnL: ₹#{position.pnl.round(2)} (#{position.pnl_pct.round(2)}%)")
    ServiceTestHelper.print_info("    HWM: ₹#{position.high_water_mark.round(2)}")
  end
end

# Test 10: Cleanup
ServiceTestHelper.print_section('10. Cleanup')
at_exit do
  active_cache.stop!
  ServiceTestHelper.print_info('ActiveCache stopped')
end

ServiceTestHelper.print_success('ActiveCache test completed')
ServiceTestHelper.print_info('ActiveCache subscribes to MarketFeedHub for real-time LTP updates')

