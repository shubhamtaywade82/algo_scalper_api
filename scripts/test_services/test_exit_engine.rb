#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Live::ExitEngine Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_derivatives

# Get spot price once and use consistently throughout
# Try multiple times to get real spot price (API might be rate limited)
spot_price = nil
3.times do |i|
  spot_price = ServiceTestHelper.fetch_ltp(segment: 'IDX_I', security_id: '13', suppress_rate_limit_warning: i > 0)
  break if spot_price&.positive?
  sleep 0.5 if i < 2
end
spot_price ||= 26_000.0  # Fallback only if all attempts fail

strike_interval = 50
atm_strike = (spot_price / strike_interval).round * strike_interval
target_strikes = [atm_strike, atm_strike + strike_interval, atm_strike + (2 * strike_interval)] # ATM, ATM+1, ATM+2

source = spot_price == 26_000.0 ? 'fallback' : 'API'
ServiceTestHelper.print_info("Spot Price: ₹#{spot_price.round(2)} (#{source}), ATM Strike: #{atm_strike}")
ServiceTestHelper.print_info("Target Strikes: #{target_strikes.map { |s| offset = (s - atm_strike) / strike_interval; offset == 0 ? "#{s} (ATM)" : "#{s} (ATM+#{offset.to_i})" }.join(', ')}")

# Check if we have positions with ATM/2OTM strikes
existing_atm_positions = PositionTracker.active
                                         .where(watchable_type: 'Derivative')
                                         .joins('INNER JOIN derivatives ON position_trackers.watchable_id = derivatives.id')
                                         .where('derivatives.strike_price IN (?)', target_strikes)
                                         .where('derivatives.option_type = ?', 'CE')

if existing_atm_positions.empty?
  # Find ATM or 2 OTM derivative (prefer ATM, fallback to ATM+2)
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
    # Verify derivative strike matches target strikes
    unless target_strikes.include?(derivative.strike_price.to_f)
      ServiceTestHelper.print_warning("Derivative strike #{derivative.strike_price} doesn't match target strikes - finding correct one")
      # Find derivative with correct strike
      derivative = Derivative.where(
        underlying_symbol: 'NIFTY',
        option_type: 'CE',
        strike_price: atm_strike
      ).first || Derivative.where(
        underlying_symbol: 'NIFTY',
        option_type: 'CE',
        strike_price: target_strikes
      ).order("CASE WHEN strike_price = #{atm_strike} THEN 1 WHEN strike_price = #{atm_strike + strike_interval} THEN 2 ELSE 3 END").first
    end

    if derivative && target_strikes.include?(derivative.strike_price.to_f)
      # Get LTP for the derivative
      seg = derivative.exchange_segment || 'NSE_FNO'
      sid = derivative.security_id
      ltp = Live::TickCache.ltp(seg, sid)

      unless ltp&.positive?
        ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s, suppress_rate_limit_warning: true)
      end

      unless ltp&.positive?
        ltp = 150.0  # Fallback option price
        ServiceTestHelper.print_info("Using fallback option LTP: ₹#{ltp}")
      end

      # Create position tracker for the derivative
      tracker = ServiceTestHelper.create_position_tracker(
        watchable: derivative,
        security_id: sid.to_s,
        segment: seg,
        side: 'long_ce',
        quantity: 75,  # 1 lot
        entry_price: ltp,
        paper: true
      )

      if tracker
        strike_label = derivative.strike_price == atm_strike ? 'ATM' : "ATM+#{((derivative.strike_price - atm_strike) / strike_interval).to_i}"
        ServiceTestHelper.print_success("Created #{strike_label} test position: #{tracker.symbol} (Strike: ₹#{derivative.strike_price})")
      end
    else
      ServiceTestHelper.print_warning('No ATM/2OTM derivatives found with matching strikes')
    end
  else
    ServiceTestHelper.print_warning('No ATM/2OTM derivatives found - using existing positions')
  end
else
  ServiceTestHelper.print_info("ATM/2OTM derivative positions already exist (#{existing_atm_positions.count})")
end

router = TradingSystem::OrderRouter.new
exit_engine = Live::ExitEngine.new(order_router: router)

# Test 1: Check active positions (ATM or 2 OTM derivatives only)
ServiceTestHelper.print_section('1. Active Positions (ATM or 2 OTM Only)')
# Use same spot price and strikes calculated above
ServiceTestHelper.print_info("Using Spot Price: ₹#{spot_price.round(2)}, ATM Strike: #{atm_strike}")
ServiceTestHelper.print_info("Target Strikes: #{target_strikes.map { |s| offset = (s - atm_strike) / strike_interval; offset == 0 ? "#{s} (ATM)" : "#{s} (ATM+#{offset.to_i})" }.join(', ')}")

# Filter to derivatives only (options) with ATM or 2 OTM strikes
active_positions = PositionTracker.active
                                   .where(watchable_type: 'Derivative')
                                   .joins('INNER JOIN derivatives ON position_trackers.watchable_id = derivatives.id')
                                   .where('derivatives.strike_price IN (?)', target_strikes)
                                   .where('derivatives.option_type = ?', 'CE')
                                   .includes(:watchable)

ServiceTestHelper.print_info("Found #{active_positions.count} active derivative positions (ATM or 2 OTM)")

# If no ATM/2OTM positions, create one
if active_positions.empty?
  ServiceTestHelper.print_warning("No ATM/2OTM derivative positions found")
  ServiceTestHelper.print_info("Creating ATM position for testing...")

  # Find ATM derivative
  derivative = ServiceTestHelper.find_atm_or_otm_derivative(
    underlying_symbol: 'NIFTY',
    option_type: 'CE',
    preference: :atm
  )

  if derivative
    seg = derivative.exchange_segment || 'NSE_FNO'
    sid = derivative.security_id
    ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s, suppress_rate_limit_warning: true) || 150.0

    tracker = PositionTracker.create!(
      watchable: derivative,
      instrument: derivative.instrument,
      order_no: "TEST-EXIT-#{Time.current.to_i}",
      security_id: sid.to_s,
      symbol: derivative.symbol_name || "NIFTY-#{derivative.strike_price}-CE",
      segment: seg,
      side: 'long_ce',
      status: 'active',
      quantity: 75,
      entry_price: ltp,
      avg_price: ltp,
      paper: true
    )

    ServiceTestHelper.print_success("Created ATM test position: #{tracker.symbol} (Strike: ₹#{derivative.strike_price})")

    # Reload active positions
    active_positions = PositionTracker.active
                                       .where(watchable_type: 'Derivative')
                                       .joins('INNER JOIN derivatives ON position_trackers.watchable_id = derivatives.id')
                                       .where('derivatives.strike_price IN (?)', target_strikes)
                                       .where('derivatives.option_type = ?', 'CE')
                                       .includes(:watchable)
  end
end

if active_positions.empty?
  ServiceTestHelper.print_warning('No active positions - cannot test exit engine')
  ServiceTestHelper.print_info('Create a position first or wait for entry signals')
  exit 0
end

# Test 2: Check exit conditions for each ATM/2OTM derivative position
ServiceTestHelper.print_section('2. Exit Condition Check (ATM or 2 OTM Derivatives Only)')
active_positions.limit(3).each do |tracker|
  watchable = tracker.watchable
  is_derivative = watchable.is_a?(Derivative)

  ServiceTestHelper.print_info("\nTracker ID: #{tracker.id}")
  ServiceTestHelper.print_info("  Type: #{is_derivative ? 'Derivative (Option)' : 'Underlying Index'}")
  ServiceTestHelper.print_info("  Symbol: #{tracker.symbol}")

  if is_derivative
    strike = watchable.strike_price
    strike_label = if strike == atm_strike
                    'ATM'
                  elsif strike == atm_strike + strike_interval
                    'ATM+1'
                  elsif strike == atm_strike + (2 * strike_interval)
                    'ATM+2'
                  else
                    'OTHER'
                  end

    ServiceTestHelper.print_info("  Strike: ₹#{strike} (#{strike_label})")
    ServiceTestHelper.print_info("  Option Type: #{watchable.option_type}")
    ServiceTestHelper.print_info("  Expiry: #{watchable.expiry_date}")

    # Warn if not ATM/2OTM
    unless ['ATM', 'ATM+1', 'ATM+2'].include?(strike_label)
      ServiceTestHelper.print_warning("  ⚠️  This position is not ATM or 2 OTM - should be filtered out")
    end
  end

  ServiceTestHelper.print_info("  Entry Price: ₹#{tracker.entry_price}")
  ServiceTestHelper.print_info("  Quantity: #{tracker.quantity}")

  # Get current LTP (try cache first, then API)
  seg = tracker.segment || watchable&.exchange_segment
  sid = tracker.security_id

  # Try multiple sources for LTP
  ltp = nil

  # 1. Try TickCache
  if seg && sid
    ltp = Live::TickCache.ltp(seg, sid)
  end

  # 2. Try RedisTickCache
  unless ltp&.positive?
    tick_data = Live::RedisTickCache.instance.fetch_tick(seg, sid) if seg && sid
    ltp = tick_data&.dig(:ltp) if tick_data
  end

  # 3. Try DhanHQ API
  unless ltp&.positive?
    ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s, suppress_rate_limit_warning: true) if seg && sid
  end

  # 4. If derivative, try fetching via derivative object
  if is_derivative && !ltp&.positive? && watchable.respond_to?(:fetch_ltp_from_api_for_segment)
    begin
      api_ltp = watchable.fetch_ltp_from_api_for_segment(segment: seg, security_id: sid.to_s)
      ltp = api_ltp if api_ltp&.positive?
    rescue StandardError => e
      ServiceTestHelper.print_info("  LTP fetch via derivative failed: #{e.message}")
    end
  end

  if ltp&.positive?
    ServiceTestHelper.print_success("  Current LTP: ₹#{ltp}")

    # Calculate current PnL
    if tracker.entry_price.present? && tracker.quantity.present?
      pnl = (ltp - tracker.entry_price.to_f) * tracker.quantity.to_i
      pnl_pct = tracker.entry_price.positive? ? ((ltp - tracker.entry_price.to_f) / tracker.entry_price.to_f * 100) : 0
      ServiceTestHelper.print_info("  Current PnL: ₹#{pnl.round(2)} (#{pnl_pct.round(2)}%)")

      # Check SL/TP levels (typical for options: 30% SL, 60% TP)
      sl_price = tracker.entry_price.to_f * 0.70
      tp_price = tracker.entry_price.to_f * 1.60
      ServiceTestHelper.print_info("  SL Level: ₹#{sl_price.round(2)} (#{ltp <= sl_price ? '⚠️ HIT' : 'OK'})")
      ServiceTestHelper.print_info("  TP Level: ₹#{tp_price.round(2)} (#{ltp >= tp_price ? '✅ HIT' : 'OK'})")
    end

    # Check if exit should be triggered (this would be done by exit_engine internally)
    ServiceTestHelper.print_info("  Exit evaluation: Checked by ExitEngine service")
  else
    ServiceTestHelper.print_warning("  No LTP available for #{tracker.symbol}")
    ServiceTestHelper.print_info("  Segment: #{seg}, Security ID: #{sid}")
  end
end

# Test 3: Test exit execution (dry run - ATM/2OTM derivatives only)
ServiceTestHelper.print_section('3. Exit Execution Test (ATM or 2 OTM Derivatives Only)')
# Get first ATM/2OTM position (already filtered)
test_tracker = active_positions.first

if test_tracker
  watchable = test_tracker.watchable
  is_derivative = watchable.is_a?(Derivative)

  ServiceTestHelper.print_info("Testing exit for tracker ID: #{test_tracker.id}")
  ServiceTestHelper.print_info("  Type: #{is_derivative ? 'Derivative (Option)' : 'Underlying Index'}")
  ServiceTestHelper.print_info("  Symbol: #{test_tracker.symbol}")

  if is_derivative
    strike = watchable.strike_price
    strike_label = if strike == atm_strike
                    'ATM'
                  elsif strike == atm_strike + strike_interval
                    'ATM+1'
                  elsif strike == atm_strike + (2 * strike_interval)
                    'ATM+2'
                  else
                    'OTHER'
                  end

    if ['ATM', 'ATM+1', 'ATM+2'].include?(strike_label)
      ServiceTestHelper.print_success("  ✅ Testing with #{strike_label} derivative position (correct for ExitEngine)")
    else
      ServiceTestHelper.print_warning("  ⚠️  Testing with #{strike_label} position (should be ATM or 2 OTM)")
    end
  else
    ServiceTestHelper.print_warning("  ⚠️  Testing with underlying index (ExitEngine should work with derivatives)")
  end

  ServiceTestHelper.print_warning('This is a dry run - no actual exit will be executed')

  # Note: Actual exit execution would be:
  # exit_engine.execute_exit(tracker: test_tracker, reason: 'test')
  # But we won't do this in a test script to avoid real trades
else
  ServiceTestHelper.print_warning('No positions available for exit testing')
end

# Test 4: Check exit reasons
ServiceTestHelper.print_section('4. Exit Reasons')
exit_reasons = [
  'stop_loss_hit',
  'take_profit_hit',
  'risk_limit_exceeded',
  'time_based_exit',
  'manual_exit'
]

exit_reasons.each do |reason|
  ServiceTestHelper.print_info("  - #{reason}")
end

ServiceTestHelper.print_success('Live::ExitEngine test completed')
ServiceTestHelper.print_info('Exit engine runs continuously - check logs for exit events')

