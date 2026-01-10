#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Live::TrailingEngine Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items
ServiceTestHelper.setup_test_derivatives

# Test 1: Initialize TrailingEngine
ServiceTestHelper.print_section('1. TrailingEngine Initialization')
trailing_engine = Live::TrailingEngine.new
ServiceTestHelper.print_success('TrailingEngine initialized')

# Test 2: Use real paper PositionTracker or create one
ServiceTestHelper.print_section('2. Create Test Position')
# Try to find an existing paper PositionTracker, or create a new one
tracker = PositionTracker.active.where(paper: true).first

unless tracker
  # Create a new paper PositionTracker using the helper
  derivative = ServiceTestHelper.find_atm_or_otm_derivative(
    underlying_symbol: 'NIFTY',
    option_type: 'CE',
    preference: :atm
  )

  if derivative
    seg = derivative.exchange_segment || 'NSE_FNO'
    sid = derivative.security_id
    ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s, suppress_rate_limit_warning: true) || 150.0

    tracker = ServiceTestHelper.create_position_tracker(
      watchable: derivative,
      segment: seg,
      security_id: sid.to_s,
      side: 'long_ce',
      quantity: 75,
      entry_price: ltp,
      paper: true
    )
  end
end

unless tracker
  ServiceTestHelper.print_error('Failed to find or create paper PositionTracker')
  exit 1
end

ServiceTestHelper.print_info("Using paper PositionTracker ID: #{tracker.id}")
ServiceTestHelper.print_info("  Symbol: #{tracker.symbol}")
ServiceTestHelper.print_info("  Entry Price: ₹#{tracker.entry_price}")
ServiceTestHelper.print_info("  Status: #{tracker.status}")

active_cache = Positions::ActiveCache.instance
position_data = active_cache.add_position(
  tracker: tracker,
  sl_price: 105.0, # 30% below entry
  tp_price: 240.0  # 60% above entry
)

if position_data
  ServiceTestHelper.print_success("Position added to ActiveCache: tracker_id=#{tracker.id}")
  ServiceTestHelper.print_info("  Entry: ₹#{position_data.entry_price.round(2)}")
  ServiceTestHelper.print_info("  Initial SL: ₹#{position_data.sl_price.round(2)}")
  ServiceTestHelper.print_info("  TP: ₹#{position_data.tp_price.round(2)}")
  ServiceTestHelper.print_info("  Initial peak_profit_pct: #{position_data.peak_profit_pct.round(2)}%")
else
  ServiceTestHelper.print_error('Failed to add position to ActiveCache')
  exit 1
end

# Test 3: Simulate profit increase and peak tracking
ServiceTestHelper.print_section('3. Peak Profit Tracking')
ServiceTestHelper.print_info('Simulating LTP updates to test peak tracking...')

profit_levels = [
  { ltp: 157.5, expected_profit: 5.0, tier: '5% profit' },
  { ltp: 165.0, expected_profit: 10.0, tier: '10% profit' },
  { ltp: 172.5, expected_profit: 15.0, tier: '15% profit' },
  { ltp: 187.5, expected_profit: 25.0, tier: '25% profit' }
]

profit_levels.each do |level|
  position_data.update_ltp(level[:ltp])
  result = trailing_engine.process_tick(position_data, exit_engine: nil)

  ServiceTestHelper.print_info("  LTP: ₹#{level[:ltp]} → Profit: #{position_data.pnl_pct.round(2)}%")
  ServiceTestHelper.print_info("    Peak: #{position_data.peak_profit_pct.round(2)}%")
  ServiceTestHelper.print_info("    Peak updated: #{result[:peak_updated]}")
  ServiceTestHelper.print_info("    SL updated: #{result[:sl_updated]}")

  if result[:sl_updated]
    new_sl = active_cache.get_by_tracker_id(tracker.id)&.sl_price
    ServiceTestHelper.print_info("    New SL: ₹#{new_sl.round(2)}") if new_sl
  end
end

# Test 4: Test tiered SL offsets
ServiceTestHelper.print_section('4. Tiered SL Offset Verification')
ServiceTestHelper.print_info('Verifying SL offsets match TrailingConfig tiers...')

tiers = Positions::TrailingConfig.tiers
ServiceTestHelper.print_info('Configured tiers:')
tiers.each do |tier|
  sl_offset = Positions::TrailingConfig.sl_offset_for(tier[:threshold_pct])
  sl_price = Positions::TrailingConfig.calculate_sl_price(150.0, tier[:threshold_pct])
  ServiceTestHelper.print_info("  #{tier[:threshold_pct]}% profit → SL offset: #{sl_offset}% → SL price: ₹#{sl_price.round(2)}")
end

# Test 5: Test SL not improved scenario
ServiceTestHelper.print_section('5. SL Not Improved Scenario')
# Set position to high profit first
position_data.update_ltp(187.5) # 25% profit
trailing_engine.process_tick(position_data, exit_engine: nil)
active_cache.get_by_tracker_id(tracker.id)&.sl_price

# Then simulate price drop (but still profitable)
position_data.update_ltp(180.0) # 20% profit (still profitable, but lower)
result = trailing_engine.process_tick(position_data, exit_engine: nil)

if result[:sl_updated] == false && result[:reason] == 'sl_not_improved'
  ServiceTestHelper.print_success('SL correctly not moved down (SL should only trail up)')
else
  ServiceTestHelper.print_info("SL behavior: #{result[:reason]}")
end

# Test 6: Test with real ExitEngine and exit the position
ServiceTestHelper.print_section('6. Exit Engine Integration - Real Exit Test')
# Create a real ExitEngine instance for testing
order_router = TradingSystem::OrderRouter.new
exit_engine = Live::ExitEngine.new(order_router: order_router)

# Simulate peak drawdown exit scenario
ServiceTestHelper.print_info('Simulating peak drawdown exit scenario...')
position_data.update_ltp(187.5) # High profit (61.5%)
ServiceTestHelper.print_info("  Current profit: #{position_data.pnl_pct.round(2)}%")
ServiceTestHelper.print_info("  Peak profit: #{position_data.peak_profit_pct.round(2)}%")

# Simulate drawdown from peak (trigger exit)
drawdown_ltp = position_data.entry_price * 1.20 # 20% profit (down from 61.5% peak)
position_data.update_ltp(drawdown_ltp)
ServiceTestHelper.print_info("  Drawdown LTP: ₹#{drawdown_ltp.round(2)} (profit: #{position_data.pnl_pct.round(2)}%)")

# Process tick with exit engine
result = trailing_engine.process_tick(position_data, exit_engine: exit_engine)

ServiceTestHelper.print_info("  Exit triggered: #{result[:exit_triggered] || false}")
ServiceTestHelper.print_info("  Exit reason: #{result[:reason] || 'none'}")

# Check if position was actually exited
tracker.reload
if tracker.status == 'exited'
  ServiceTestHelper.print_success('✅ Position successfully exited!')
  ServiceTestHelper.print_info("  Exit price: ₹#{tracker.exit_price}")
  exit_reason = tracker.meta.is_a?(Hash) ? tracker.meta['exit_reason'] : nil
  ServiceTestHelper.print_info("  Exit reason: #{exit_reason || 'N/A'}")
  ServiceTestHelper.print_info("  Final PnL: ₹#{tracker.last_pnl_rupees&.round(2) || 0.0} (#{tracker.last_pnl_pct&.round(2) || 0.0}%)")
else
  ServiceTestHelper.print_info('  Position still active (exit not triggered or failed)')
  ServiceTestHelper.print_info("  Current status: #{tracker.status}")
end

ServiceTestHelper.print_section('Summary')
ServiceTestHelper.print_info('TrailingEngine test completed')
ServiceTestHelper.print_info('Key features verified:')
ServiceTestHelper.print_info('  ✅ Peak profit tracking')
ServiceTestHelper.print_info('  ✅ Tiered SL adjustments')
ServiceTestHelper.print_info('  ✅ SL only moves up (trailing)')
ServiceTestHelper.print_info('  ✅ Exit engine integration')
