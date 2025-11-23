#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('RedisPnlCache Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_position_tracker(paper: true)

pnl_cache = Live::RedisPnlCache.instance

# Test 1: Store PnL for a test tracker
ServiceTestHelper.print_section('1. Storing PnL Data')
test_tracker_id = 999_999
test_pnl = 1500.50
test_pnl_pct = 5.25
test_ltp = 25_500.0
test_hwm = 2000.0

result = pnl_cache.store_pnl(
  tracker_id: test_tracker_id,
  pnl: test_pnl,
  pnl_pct: test_pnl_pct,
  ltp: test_ltp,
  hwm: test_hwm,
  timestamp: Time.current
)

ServiceTestHelper.check_condition(
  result.present?,
  'PnL data stored successfully',
  'Failed to store PnL data'
)

# Test 2: Fetch stored PnL
ServiceTestHelper.print_section('2. Fetching Stored PnL')
fetched = pnl_cache.fetch_pnl(test_tracker_id)

if fetched.present?
  ServiceTestHelper.print_success('PnL data fetched')
  ServiceTestHelper.print_info("PnL data:\n#{ServiceTestHelper.format_hash(fetched)}")

  ServiceTestHelper.check_condition(
    fetched[:pnl].to_f == test_pnl,
    "PnL matches: ₹#{fetched[:pnl]}",
    "PnL mismatch: expected ₹#{test_pnl}, got #{fetched[:pnl]}"
  )
else
  ServiceTestHelper.print_error('Failed to fetch PnL data')
end

# Test 3: Update PnL (HWM should increase)
ServiceTestHelper.print_section('3. Updating PnL (HWM Test)')
new_pnl = 2500.75
new_hwm = 3000.0

pnl_cache.store_pnl(
  tracker_id: test_tracker_id,
  pnl: new_pnl,
  pnl_pct: 8.5,
  ltp: 26_000.0,
  hwm: new_hwm,
  timestamp: Time.current
)

updated = pnl_cache.fetch_pnl(test_tracker_id)
if updated && updated[:hwm_pnl].to_f == new_hwm
  ServiceTestHelper.print_success("HWM updated: ₹#{updated[:hwm_pnl]}")
else
  ServiceTestHelper.print_error('HWM update failed')
end

# Test 4: Test with real PositionTracker (if available)
ServiceTestHelper.print_section('4. Real PositionTracker Test')
tracker = PositionTracker.active.first

if tracker
  ServiceTestHelper.print_info("Testing with tracker ID: #{tracker.id}")
  ServiceTestHelper.print_info("Testing with tracker ID: #{tracker.id}")

  # Calculate PnL
  if tracker.entry_price.present? && tracker.quantity.present?
    # Get LTP using the watchable's (derivative/instrument) ltp() method
    # This uses InstrumentHelpers.ltp() which handles WebSocket + API automatically
    ltp = nil

    if tracker.watchable.respond_to?(:ltp)
      # Use the derivative/instrument's built-in ltp() method (InstrumentHelpers)
      ltp = tracker.watchable.ltp&.to_f
      ServiceTestHelper.print_info("Got LTP from watchable.ltp(): ₹#{ltp}") if ltp&.positive?
    end

    # Fallback: Try TickCache directly
    unless ltp&.positive?
      seg = tracker.segment || tracker.watchable&.exchange_segment
      sid = tracker.security_id
      ltp = Live::TickCache.ltp(seg, sid)&.to_f if seg && sid
    end

    # Last resort: Direct API call
    unless ltp&.positive?
      seg = tracker.segment || tracker.watchable&.exchange_segment
      sid = tracker.security_id
      ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s) if seg && sid
    end

    if ltp&.positive?
      entry = tracker.entry_price.to_f
      qty = tracker.quantity.to_i
      pnl = (ltp - entry) * qty
      pnl_pct = entry.positive? ? ((ltp - entry) / entry * 100) : 0

      pnl_cache.store_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pnl_pct,
        ltp: ltp,
        hwm: tracker.high_water_mark_pnl&.to_f || pnl,
        timestamp: Time.current
      )

      fetched_tracker_pnl = pnl_cache.fetch_pnl(tracker.id)
      if fetched_tracker_pnl
        ServiceTestHelper.print_success("Tracker PnL stored: ₹#{fetched_tracker_pnl[:pnl]}")
      else
        ServiceTestHelper.print_error('Failed to fetch tracker PnL')
      end
    else
      ServiceTestHelper.print_warning("No LTP available for tracker #{tracker.id}")
    end
  else
    ServiceTestHelper.print_warning("Tracker #{tracker.id} missing entry_price or quantity")
  end
else
  ServiceTestHelper.print_warning('No active PositionTracker found')
end

# Test 5: Clear tracker
ServiceTestHelper.print_section('5. Clear Tracker Test')
pnl_cache.clear_tracker(test_tracker_id)
cleared = pnl_cache.fetch_pnl(test_tracker_id)
ServiceTestHelper.check_condition(
  cleared.blank?,
  'Tracker PnL cleared successfully',
  'Failed to clear tracker PnL'
)

ServiceTestHelper.print_success('RedisPnlCache test completed')

