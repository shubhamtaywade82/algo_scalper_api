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
    # Get LTP using the SAME method as RiskManagerService.get_paper_ltp()
    # This matches production behavior exactly
    seg = tracker.segment || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
    sid = tracker.security_id
    ltp = nil

    # 1. Try WebSocket TickCache first (fastest, no API call) - matches RiskManagerService
    if seg && sid
      ltp = Live::TickCache.ltp(seg, sid)&.to_f
      ServiceTestHelper.print_info("Got LTP from TickCache: ₹#{ltp}") if ltp&.positive?
    end

    # 2. Try RedisTickCache fallback - matches RiskManagerService
    unless ltp&.positive?
      begin
        tick_data = Live::RedisTickCache.instance.fetch_tick(seg, sid) if seg && sid
        ltp = tick_data[:ltp]&.to_f if tick_data && tick_data[:ltp]&.to_f&.positive?
        ServiceTestHelper.print_info("Got LTP from RedisTickCache: ₹#{ltp}") if ltp&.positive?
      rescue StandardError => e
        ServiceTestHelper.print_warning("RedisTickCache error: #{e.message}")
      end
    end

    # 3. Try tradable's fetch_ltp_from_api_for_segment() - matches RiskManagerService
    unless ltp&.positive?
      tradable = tracker.watchable || tracker.instrument
      if tradable && seg && sid
        begin
          ltp = tradable.fetch_ltp_from_api_for_segment(segment: seg, security_id: sid)&.to_f
          ServiceTestHelper.print_info("Got LTP from tradable.fetch_ltp_from_api_for_segment(): ₹#{ltp}") if ltp&.positive?
        rescue StandardError => e
          ServiceTestHelper.print_warning("fetch_ltp_from_api_for_segment error: #{e.message}")
        end
      end
    end

    # 4. Last resort: Direct API call - matches RiskManagerService
    unless ltp&.positive?
      ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s) if seg && sid
      ServiceTestHelper.print_info("Got LTP from direct API: ₹#{ltp}") if ltp&.positive?
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

# Test 5: Test Profit/Loss Scenarios by Manipulating LTPs
ServiceTestHelper.print_section('5. Profit/Loss Scenarios (LTP Manipulation)')
tracker = PositionTracker.active.first

if tracker && tracker.entry_price.present? && tracker.quantity.present?
  entry_price = tracker.entry_price.to_f
  quantity = tracker.quantity.to_i
  seg = tracker.segment || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
  sid = tracker.security_id

  ServiceTestHelper.print_info("Testing with tracker ID: #{tracker.id}")
  ServiceTestHelper.print_info("Entry Price: ₹#{entry_price}, Quantity: #{quantity}")
  ServiceTestHelper.print_info("Segment: #{seg}, Security ID: #{sid}")

  # Scenario 1: PROFIT - LTP higher than entry
  ServiceTestHelper.print_info('')
  ServiceTestHelper.print_info('--- Scenario 1: PROFIT ---')
  profit_ltp = entry_price * 1.10 # 10% profit
  ServiceTestHelper.print_info("Setting LTP to ₹#{profit_ltp} (10% above entry)")

  # Store LTP in RedisTickCache (simulating market movement)
  Live::RedisTickCache.instance.store_tick(
    segment: seg,
    security_id: sid.to_s,
    data: { ltp: profit_ltp, timestamp: Time.current.to_i }
  )

  # Wait a moment for cache to update
  sleep 0.1

  # Calculate expected PnL
  expected_pnl = (profit_ltp - entry_price) * quantity
  expected_pnl_pct = ((profit_ltp - entry_price) / entry_price) * 100

  # Store PnL (simulating what RiskManagerService would do)
  pnl_cache.store_pnl(
    tracker_id: tracker.id,
    pnl: expected_pnl,
    pnl_pct: expected_pnl_pct,
    ltp: profit_ltp,
    hwm: expected_pnl, # First profit, so HWM = current PnL
    timestamp: Time.current
  )

  # Verify
  profit_data = pnl_cache.fetch_pnl(tracker.id)
  if profit_data
    profit_ok = (profit_data[:pnl].to_f - expected_pnl).abs < 0.01
    pct_ok = (profit_data[:pnl_pct].to_f - expected_pnl_pct).abs < 0.01
    hwm_ok = (profit_data[:hwm_pnl].to_f - expected_pnl).abs < 0.01

    ServiceTestHelper.check_condition(
      profit_ok && pct_ok && hwm_ok,
      "Profit scenario: PnL=₹#{profit_data[:pnl]}, PnL%=#{profit_data[:pnl_pct].round(2)}%, HWM=₹#{profit_data[:hwm_pnl]}",
      "Profit scenario failed - PnL: #{profit_ok ? '✅' : '❌'}, PnL%: #{pct_ok ? '✅' : '❌'}, HWM: #{hwm_ok ? '✅' : '❌'}"
    )
  else
    ServiceTestHelper.print_error('Failed to fetch profit PnL data')
  end

  # Scenario 2: LOSS - LTP lower than entry
  ServiceTestHelper.print_info('')
  ServiceTestHelper.print_info('--- Scenario 2: LOSS ---')
  loss_ltp = entry_price * 0.95 # 5% loss
  ServiceTestHelper.print_info("Setting LTP to ₹#{loss_ltp} (5% below entry)")

  # Store LTP in RedisTickCache
  Live::RedisTickCache.instance.store_tick(
    segment: seg,
    security_id: sid.to_s,
    data: { ltp: loss_ltp, timestamp: Time.current.to_i }
  )

  sleep 0.1

  # Calculate expected PnL (negative)
  expected_loss = (loss_ltp - entry_price) * quantity
  expected_loss_pct = ((loss_ltp - entry_price) / entry_price) * 100

  # Store PnL (HWM should remain at previous profit level)
  previous_hwm = profit_data[:hwm_pnl].to_f
  pnl_cache.store_pnl(
    tracker_id: tracker.id,
    pnl: expected_loss,
    pnl_pct: expected_loss_pct,
    ltp: loss_ltp,
    hwm: previous_hwm, # HWM should remain at peak (previous profit)
    timestamp: Time.current
  )

  # Verify
  loss_data = pnl_cache.fetch_pnl(tracker.id)
  if loss_data
    loss_ok = (loss_data[:pnl].to_f - expected_loss).abs < 0.01
    loss_pct_ok = (loss_data[:pnl_pct].to_f - expected_loss_pct).abs < 0.01
    hwm_unchanged = (loss_data[:hwm_pnl].to_f - previous_hwm).abs < 0.01

    ServiceTestHelper.check_condition(
      loss_ok && loss_pct_ok && hwm_unchanged,
      "Loss scenario: PnL=₹#{loss_data[:pnl]}, PnL%=#{loss_data[:pnl_pct].round(2)}%, HWM=₹#{loss_data[:hwm_pnl]} (unchanged)",
      "Loss scenario failed - PnL: #{loss_ok ? '✅' : '❌'}, PnL%: #{loss_pct_ok ? '✅' : '❌'}, HWM unchanged: #{hwm_unchanged ? '✅' : '❌'}"
    )
  else
    ServiceTestHelper.print_error('Failed to fetch loss PnL data')
  end

  # Scenario 3: BIGGER PROFIT - New HWM
  ServiceTestHelper.print_info('')
  ServiceTestHelper.print_info('--- Scenario 3: BIGGER PROFIT (New HWM) ---')
  bigger_profit_ltp = entry_price * 1.15 # 15% profit (higher than previous 10%)
  ServiceTestHelper.print_info("Setting LTP to ₹#{bigger_profit_ltp} (15% above entry)")

  # Store LTP in RedisTickCache
  Live::RedisTickCache.instance.store_tick(
    segment: seg,
    security_id: sid.to_s,
    data: { ltp: bigger_profit_ltp, timestamp: Time.current.to_i }
  )

  sleep 0.1

  # Calculate expected PnL
  expected_bigger_pnl = (bigger_profit_ltp - entry_price) * quantity
  expected_bigger_pnl_pct = ((bigger_profit_ltp - entry_price) / entry_price) * 100

  # Store PnL (HWM should update to new higher value)
  pnl_cache.store_pnl(
    tracker_id: tracker.id,
    pnl: expected_bigger_pnl,
    pnl_pct: expected_bigger_pnl_pct,
    ltp: bigger_profit_ltp,
    hwm: expected_bigger_pnl, # New HWM = current higher profit
    timestamp: Time.current
  )

  # Verify
  bigger_profit_data = pnl_cache.fetch_pnl(tracker.id)
  if bigger_profit_data
    bigger_pnl_ok = (bigger_profit_data[:pnl].to_f - expected_bigger_pnl).abs < 0.01
    bigger_pct_ok = (bigger_profit_data[:pnl_pct].to_f - expected_bigger_pnl_pct).abs < 0.01
    hwm_updated = (bigger_profit_data[:hwm_pnl].to_f - expected_bigger_pnl).abs < 0.01
    hwm_higher = bigger_profit_data[:hwm_pnl].to_f > previous_hwm

    ServiceTestHelper.check_condition(
      bigger_pnl_ok && bigger_pct_ok && hwm_updated && hwm_higher,
      "Bigger profit scenario: PnL=₹#{bigger_profit_data[:pnl]}, PnL%=#{bigger_profit_data[:pnl_pct].round(2)}%, HWM=₹#{bigger_profit_data[:hwm_pnl]} (updated)",
      "Bigger profit scenario failed - PnL: #{bigger_pnl_ok ? '✅' : '❌'}, PnL%: #{bigger_pct_ok ? '✅' : '❌'}, HWM updated: #{hwm_updated ? '✅' : '❌'}, HWM higher: #{hwm_higher ? '✅' : '❌'}"
    )
  else
    ServiceTestHelper.print_error('Failed to fetch bigger profit PnL data')
  end

  # Scenario 4: Partial Recovery - HWM should remain at peak
  ServiceTestHelper.print_info('')
  ServiceTestHelper.print_info('--- Scenario 4: PARTIAL RECOVERY (HWM Preserved) ---')
  recovery_ltp = entry_price * 1.12 # 12% profit (between 10% and 15%)
  ServiceTestHelper.print_info("Setting LTP to ₹#{recovery_ltp} (12% above entry, but below peak)")

  # Store LTP in RedisTickCache
  Live::RedisTickCache.instance.store_tick(
    segment: seg,
    security_id: sid.to_s,
    data: { ltp: recovery_ltp, timestamp: Time.current.to_i }
  )

  sleep 0.1

  # Calculate expected PnL
  expected_recovery_pnl = (recovery_ltp - entry_price) * quantity
  expected_recovery_pnl_pct = ((recovery_ltp - entry_price) / entry_price) * 100
  peak_hwm = bigger_profit_data[:hwm_pnl].to_f

  # Store PnL (HWM should remain at previous peak, not update)
  pnl_cache.store_pnl(
    tracker_id: tracker.id,
    pnl: expected_recovery_pnl,
    pnl_pct: expected_recovery_pnl_pct,
    ltp: recovery_ltp,
    hwm: peak_hwm, # HWM should remain at peak (15% profit)
    timestamp: Time.current
  )

  # Verify
  recovery_data = pnl_cache.fetch_pnl(tracker.id)
  if recovery_data
    recovery_pnl_ok = (recovery_data[:pnl].to_f - expected_recovery_pnl).abs < 0.01
    recovery_pct_ok = (recovery_data[:pnl_pct].to_f - expected_recovery_pnl_pct).abs < 0.01
    hwm_preserved = (recovery_data[:hwm_pnl].to_f - peak_hwm).abs < 0.01

    ServiceTestHelper.check_condition(
      recovery_pnl_ok && recovery_pct_ok && hwm_preserved,
      "Recovery scenario: PnL=₹#{recovery_data[:pnl]}, PnL%=#{recovery_data[:pnl_pct].round(2)}%, HWM=₹#{recovery_data[:hwm_pnl]} (preserved at peak)",
      "Recovery scenario failed - PnL: #{recovery_pnl_ok ? '✅' : '❌'}, PnL%: #{recovery_pct_ok ? '✅' : '❌'}, HWM preserved: #{hwm_preserved ? '✅' : '❌'}"
    )
  else
    ServiceTestHelper.print_error('Failed to fetch recovery PnL data')
  end

  ServiceTestHelper.print_success('All profit/loss scenarios completed')
else
  ServiceTestHelper.print_warning('Skipping profit/loss scenarios - no active tracker with entry_price/quantity')
end

# Test 6: Clear tracker
ServiceTestHelper.print_section('6. Clear Tracker Test')
pnl_cache.clear_tracker(test_tracker_id)
cleared = pnl_cache.fetch_pnl(test_tracker_id)
ServiceTestHelper.check_condition(
  cleared.blank?,
  'Tracker PnL cleared successfully',
  'Failed to clear tracker PnL'
)

ServiceTestHelper.print_success('RedisPnlCache test completed')

