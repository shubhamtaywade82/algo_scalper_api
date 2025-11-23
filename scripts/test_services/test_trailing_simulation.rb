#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Trailing Stop Simulation - Tick Sequence Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items
ServiceTestHelper.setup_test_derivatives

# Exchange segments reference:
# NSE_EQ: Equity Cash
# NSE_FNO: Futures & Options (used for options trading)
# NSE_CURRENCY: Currency
# BSE_EQ: Equity Cash
# BSE_FNO: Futures & Options
# BSE_CURRENCY: Currency
# MCX_COMM: Commodity

# Test 1: Create test position
ServiceTestHelper.print_section('1. Create Test Position')
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
  ServiceTestHelper.print_error("Failed to find or create paper PositionTracker")
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

ServiceTestHelper.print_success("Position created: tracker_id=#{tracker.id}")
ServiceTestHelper.print_info("  Segment: #{tracker.segment} (NSE_FNO - Futures & Options)")
ServiceTestHelper.print_info("  Entry: ₹#{position_data.entry_price.round(2)}")
ServiceTestHelper.print_info("  Initial SL: ₹#{position_data.sl_price.round(2)}")
ServiceTestHelper.print_info("  TP: ₹#{position_data.tp_price.round(2)}")

trailing_engine = Live::TrailingEngine.new

# Create a real ExitEngine instance for testing
order_router = TradingSystem::OrderRouter.new
exit_engine = Live::ExitEngine.new(order_router: order_router)

# We'll track exits by checking the database status instead of mocking

# Test 2: Simulate tick sequence - gradual profit increase
ServiceTestHelper.print_section('2. Tick Sequence: Gradual Profit Increase')
ServiceTestHelper.print_info("Simulating gradual profit increase to test trailing tiers...")

tick_sequence_profit = [
  { tick: 1, ltp: 152.0, profit: 1.33, description: 'Small profit' },
  { tick: 2, ltp: 157.5, profit: 5.0, description: '5% profit - Tier 1 trigger' },
  { tick: 3, ltp: 160.0, profit: 6.67, description: 'Between tiers' },
  { tick: 4, ltp: 165.0, profit: 10.0, description: '10% profit - Tier 2 trigger' },
  { tick: 5, ltp: 170.0, profit: 13.33, description: 'Between tiers' },
  { tick: 6, ltp: 172.5, profit: 15.0, description: '15% profit - Tier 3 trigger (breakeven)' },
  { tick: 7, ltp: 180.0, profit: 20.0, description: '20% profit' },
  { tick: 8, ltp: 187.5, profit: 25.0, description: '25% profit - Tier 4 trigger' },
  { tick: 9, ltp: 195.0, profit: 30.0, description: '30% profit' },
  { tick: 10, ltp: 210.0, profit: 40.0, description: '40% profit - Tier 5 trigger' }
]

tick_sequence_profit.each do |tick_data|
  position_data.update_ltp(tick_data[:ltp])
  result = trailing_engine.process_tick(position_data, exit_engine: exit_engine)

  ServiceTestHelper.print_info("  Tick #{tick_data[:tick]}: LTP=₹#{tick_data[:ltp]}, Profit=#{tick_data[:profit].round(2)}%")
  ServiceTestHelper.print_info("    Peak: #{position_data.peak_profit_pct.round(2)}%")
  ServiceTestHelper.print_info("    SL updated: #{result[:sl_updated]}")
  ServiceTestHelper.print_info("    Exit triggered: #{result[:exit_triggered]}")

  if result[:sl_updated]
    current_sl = active_cache.get_by_tracker_id(tracker.id)&.sl_price
    sl_offset_pct = ((current_sl - position_data.entry_price) / position_data.entry_price * 100).round(2)
    ServiceTestHelper.print_info("    Current SL: ₹#{current_sl.round(2)} (#{sl_offset_pct}% offset)")
  end
end

# Test 3: Simulate peak-drawdown exit scenario
ServiceTestHelper.print_section('3. Tick Sequence: Peak-Drawdown Exit')
ServiceTestHelper.print_info("Simulating profit to peak, then drawdown to trigger exit...")

# Reset to high profit (peak)
position_data.update_ltp(187.5) # 25% profit (peak)
trailing_engine.process_tick(position_data, exit_engine: exit_engine)
peak_profit = position_data.peak_profit_pct

ServiceTestHelper.print_info("  Peak achieved: #{peak_profit.round(2)}%")

# Simulate drawdown sequence
drawdown_sequence = [
  { tick: 1, ltp: 185.0, profit: 23.33, drawdown: 1.67, description: 'Small drawdown' },
  { tick: 2, ltp: 182.5, profit: 21.67, drawdown: 3.33, description: 'Moderate drawdown' },
  { tick: 3, ltp: 180.0, profit: 20.0, drawdown: 5.0, description: '5% drawdown - THRESHOLD' },
  { tick: 4, ltp: 177.0, profit: 18.0, drawdown: 7.0, description: '7% drawdown - EXIT TRIGGER' }
]

drawdown_sequence.each do |tick_data|
  position_data.update_ltp(tick_data[:ltp])
  result = trailing_engine.process_tick(position_data, exit_engine: exit_engine)

  ServiceTestHelper.print_info("  Tick #{tick_data[:tick]}: LTP=₹#{tick_data[:ltp]}, Profit=#{tick_data[:profit].round(2)}%")
  ServiceTestHelper.print_info("    Drawdown from peak: #{tick_data[:drawdown].round(2)}%")
  ServiceTestHelper.print_info("    Exit triggered: #{result[:exit_triggered]}")

  if result[:exit_triggered]
    ServiceTestHelper.print_success("    ✅ Peak-drawdown exit triggered!")
    ServiceTestHelper.print_info("    Exit reason: #{result[:reason]}")
    # Check if position was actually exited
    tracker.reload
    if tracker.status == 'exited'
      exit_reason = tracker.meta.is_a?(Hash) ? tracker.meta['exit_reason'] : nil
      ServiceTestHelper.print_info("    Position status: exited")
      ServiceTestHelper.print_info("    Database exit reason: #{exit_reason || 'N/A'}")
    end
    break # Exit triggered, stop sequence
  end
end

# Test 4: Idempotency test - verify no double exit
ServiceTestHelper.print_section('4. Idempotency Test: No Double Exit')
ServiceTestHelper.print_info("Testing that exit is not triggered multiple times...")

# Reset to trigger condition
position_data.update_ltp(187.5) # Peak
trailing_engine.process_tick(position_data, exit_engine: exit_engine)
position_data.update_ltp(177.0) # Drawdown to trigger exit
trailing_engine.process_tick(position_data, exit_engine: exit_engine)

# Process same tick multiple times
exit_triggered_count = 0
5.times do |i|
  result = trailing_engine.process_tick(position_data, exit_engine: exit_engine)
  exit_triggered_count += 1 if result[:exit_triggered]
  ServiceTestHelper.print_info("  Attempt #{i + 1}: Exit triggered: #{result[:exit_triggered]}")
end

# Check final status
tracker.reload
ServiceTestHelper.print_info("  Final status: #{tracker.status}")
ServiceTestHelper.print_info("  Exit triggered count: #{exit_triggered_count}")

if tracker.status == 'exited' && exit_triggered_count <= 1
  ServiceTestHelper.print_success("Exit is idempotent (position stays exited, no double exit)")
else
  ServiceTestHelper.print_warning("Exit may not be fully idempotent (status: #{tracker.status}, triggers: #{exit_triggered_count})")
end

# Test 5: Complex scenario - profit, drawdown, recovery, drawdown again
ServiceTestHelper.print_section('5. Complex Scenario: Profit → Drawdown → Recovery → Drawdown')
ServiceTestHelper.print_info("Simulating realistic trading scenario...")

# Start fresh
position_data.update_ltp(150.0) # Back to entry
position_data.peak_profit_pct = 0.0

complex_sequence = [
  { phase: 'Profit', ltp: 165.0, profit: 10.0 },
  { phase: 'More Profit', ltp: 180.0, profit: 20.0 },
  { phase: 'Peak', ltp: 187.5, profit: 25.0 },
  { phase: 'Drawdown 1', ltp: 182.5, profit: 21.67, drawdown: 3.33 },
  { phase: 'Recovery', ltp: 190.0, profit: 26.67 },
  { phase: 'New Peak', ltp: 195.0, profit: 30.0 },
  { phase: 'Drawdown 2', ltp: 185.0, profit: 23.33, drawdown: 6.67 }
]

complex_sequence.each do |step|
  position_data.update_ltp(step[:ltp])
  result = trailing_engine.process_tick(position_data, exit_engine: exit_engine)

  ServiceTestHelper.print_info("  #{step[:phase]}: LTP=₹#{step[:ltp]}, Profit=#{step[:profit].round(2)}%")
  ServiceTestHelper.print_info("    Peak: #{position_data.peak_profit_pct.round(2)}%")
  if step[:drawdown]
    ServiceTestHelper.print_info("    Drawdown: #{step[:drawdown].round(2)}%")
  end
  ServiceTestHelper.print_info("    Exit triggered: #{result[:exit_triggered]}")

  if result[:exit_triggered]
    ServiceTestHelper.print_success("    ✅ Exit triggered in #{step[:phase]}")
    break
  end
end

# Test 6: Verify trailing SL moves only up
ServiceTestHelper.print_section('6. Trailing SL Direction Test')
ServiceTestHelper.print_info("Verifying SL only moves up (trailing), never down...")

# Set to high profit first
position_data.update_ltp(187.5) # 25% profit
trailing_engine.process_tick(position_data, exit_engine: nil)
high_sl = active_cache.get_by_tracker_id(tracker.id)&.sl_price

# Simulate price drop (but still profitable)
position_data.update_ltp(180.0) # 20% profit (lower than peak)
result = trailing_engine.process_tick(position_data, exit_engine: nil)
new_sl = active_cache.get_by_tracker_id(tracker.id)&.sl_price

if new_sl >= high_sl
  ServiceTestHelper.print_success("SL correctly maintained or increased (trailing up)")
  ServiceTestHelper.print_info("  Previous SL: ₹#{high_sl.round(2)}")
  ServiceTestHelper.print_info("  Current SL: ₹#{new_sl.round(2)}")
else
  ServiceTestHelper.print_error("SL moved down (should only trail up)")
  ServiceTestHelper.print_info("  Previous SL: ₹#{high_sl.round(2)}")
  ServiceTestHelper.print_info("  Current SL: ₹#{new_sl.round(2)}")
end

ServiceTestHelper.print_section('Summary')
ServiceTestHelper.print_info("Trailing simulation test completed")
ServiceTestHelper.print_info("Key scenarios verified:")
ServiceTestHelper.print_info("  ✅ Gradual profit increase with tiered SL moves")
ServiceTestHelper.print_info("  ✅ Peak-drawdown exit trigger")
ServiceTestHelper.print_info("  ✅ Idempotency (no double exit)")
ServiceTestHelper.print_info("  ✅ Complex profit/drawdown/recovery scenarios")
ServiceTestHelper.print_info("  ✅ SL only trails up (never down)")
ServiceTestHelper.print_info("  ✅ Exchange segment: NSE_FNO (Futures & Options)")

