#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Entries::EntryGuard Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items
ServiceTestHelper.setup_test_derivatives

# Test 1: Check exposure limits
ServiceTestHelper.print_section('1. Exposure Limits Check')
indices = AlgoConfig.fetch[:indices] || []
nifty_index = indices.find { |idx| ['NIFTY', :NIFTY].include?(idx[:key]) } || {}
index_cfg = nifty_index[:config] || nifty_index || {}

if index_cfg.any?
  # Get NIFTY instrument
  nifty_instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')

  if nifty_instrument
    max_same_side = index_cfg[:max_same_side] || 1
    exposure_ok = Entries::EntryGuard.exposure_ok?(
      instrument: nifty_instrument,
      side: 'long_ce',
      max_same_side: max_same_side
    )

    if exposure_ok
      ServiceTestHelper.print_success("Exposure check passed (max_same_side: #{max_same_side})")
    else
      ServiceTestHelper.print_warning("Exposure check failed - may have reached limit (max_same_side: #{max_same_side})")
    end

    # Check current active positions
    active_positions = PositionTracker.active.where(side: 'long_ce').count
    ServiceTestHelper.print_info("Current active positions (long_ce): #{active_positions}/#{max_same_side}")
  else
    ServiceTestHelper.print_warning('NIFTY instrument not found')
  end
else
  ServiceTestHelper.print_warning('NIFTY index config not found')
end

# Test 2: Test cooldown mechanism
ServiceTestHelper.print_section('2. Cooldown Mechanism Test')
test_symbol = 'NIFTY-Nov2025-26050-CE'
cooldown_sec = index_cfg[:cooldown_sec] || 180

# Check if cooldown is active
cooldown_active = Entries::EntryGuard.cooldown_active?(test_symbol, cooldown_sec)
if cooldown_active
  ServiceTestHelper.print_warning("Cooldown is active for #{test_symbol}")
else
  ServiceTestHelper.print_success("No cooldown for #{test_symbol} (cooldown: #{cooldown_sec}s)")
end

# Test 3: Test try_enter with a derivative pick
ServiceTestHelper.print_section('3. Try Enter Test (with Derivative Pick)')
if index_cfg.any? && nifty_instrument
  # Find ATM or 2 OTM derivative for testing (prefer ATM, fallback to ATM+2)
  derivative = ServiceTestHelper.find_atm_or_otm_derivative(
    underlying_symbol: 'NIFTY',
    option_type: 'CE',
    preference: :atm
  ) || ServiceTestHelper.find_atm_or_otm_derivative(
    underlying_symbol: 'NIFTY',
    option_type: 'CE',
    preference: :atm_plus_2
  )

  # Fallback to any CE derivative if ATM/OTM not found
  derivative ||= Derivative.where(underlying_symbol: 'NIFTY', option_type: 'CE').first

  if derivative
    # Get LTP for the derivative
    seg = derivative.exchange_segment || 'NSE_FNO'
    sid = derivative.security_id
    ltp = Live::TickCache.ltp(seg, sid)

    unless ltp&.positive?
      ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s, suppress_rate_limit_warning: true)
    end

    unless ltp&.positive?
      ltp = 150.0 # Fallback
      ServiceTestHelper.print_warning("Using fallback LTP: ₹#{ltp}")
    end

    # Build pick hash (as expected by try_enter)
    pick = {
      segment: seg,
      security_id: sid.to_s,
      symbol: derivative.symbol_name || "NIFTY-#{derivative.strike_price}-CE",
      ltp: ltp,
      lot_size: derivative.lot_size || 75,
      derivative_id: derivative.id
    }

    ServiceTestHelper.print_info('Testing entry with:')
    ServiceTestHelper.print_info("  Symbol: #{pick[:symbol]}")
    ServiceTestHelper.print_info("  Strike: #{derivative.strike_price}")
    ServiceTestHelper.print_info("  LTP: ₹#{ltp}")
    ServiceTestHelper.print_info("  Lot Size: #{pick[:lot_size]}")

    # Try to enter (this will check exposure, cooldown, calculate quantity, etc.)
    result = Entries::EntryGuard.try_enter(
      index_cfg: index_cfg,
      pick: pick,
      direction: :bullish,
      scale_multiplier: 1
    )

    if result
      ServiceTestHelper.print_success('Entry attempt succeeded (position created)')
      # Check if position was created
      new_position = PositionTracker.active.where(security_id: sid.to_s).order(created_at: :desc).first
      if new_position
        ServiceTestHelper.print_info("  Position created: #{new_position.order_no}")
        ServiceTestHelper.print_info("  Quantity: #{new_position.quantity}")
        ServiceTestHelper.print_info("  Entry Price: ₹#{new_position.entry_price}")
      end
    else
      ServiceTestHelper.print_warning('Entry attempt failed (may be blocked by guard rules)')
      ServiceTestHelper.print_info('Possible reasons:')
      ServiceTestHelper.print_info('  - Exposure limit reached')
      ServiceTestHelper.print_info('  - Cooldown active')
      ServiceTestHelper.print_info('  - Insufficient capital for quantity calculation')
      ServiceTestHelper.print_info('  - Invalid LTP or pick data')
    end
  else
    ServiceTestHelper.print_warning('No derivatives found for testing')
  end
else
  ServiceTestHelper.print_warning('Skipping try_enter test - missing config or instrument')
end

# Test 4: Check entry limits and active positions
ServiceTestHelper.print_section('4. Active Positions Summary')
active_positions = PositionTracker.active.count
ServiceTestHelper.print_info("Total active positions: #{active_positions}")

if active_positions.positive?
  PositionTracker.active.limit(5).each do |tracker|
    ServiceTestHelper.print_info("  - #{tracker.symbol}: #{tracker.quantity} @ ₹#{tracker.entry_price} (Side: #{tracker.side})")
  end
end

# Test 5: Test pyramiding rules (if applicable)
ServiceTestHelper.print_section('5. Pyramiding Rules Check')
if active_positions >= 1
  first_position = PositionTracker.active.where(side: 'long_ce').first
  if first_position
    pyramiding_allowed = Entries::EntryGuard.pyramiding_allowed?(first_position)
    pnl = first_position.last_pnl_rupees || 0

    if pyramiding_allowed
      ServiceTestHelper.print_success("Pyramiding allowed - first position PnL: ₹#{pnl.round(2)}")
    else
      ServiceTestHelper.print_info("Pyramiding not allowed - first position PnL: ₹#{pnl.round(2)}")
      ServiceTestHelper.print_info('  (Second position only allowed if first is profitable for 5+ minutes)')
    end
  end
end

ServiceTestHelper.print_success('Entries::EntryGuard test completed')
ServiceTestHelper.print_info('EntryGuard uses class methods - call Entries::EntryGuard.try_enter() directly')
