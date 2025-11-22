#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Capital::Allocator Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_instruments

# Test 1: Get available cash (use hardcoded fallback for reliability)
ServiceTestHelper.print_section('1. Available Cash')
available_cash = ServiceTestHelper.get_test_capital(fallback: 100_000.0)
ServiceTestHelper.print_info("Available cash: ₹#{available_cash}")

# Test 2: Check paper trading mode
ServiceTestHelper.print_section('2. Paper Trading Mode')
paper_enabled = Capital::Allocator.paper_trading_enabled?
ServiceTestHelper.print_info("Paper trading enabled: #{paper_enabled}")

# Test 3: Test quantity calculation using actual derivatives (ATM or 2 OTM)
ServiceTestHelper.print_section('3. Quantity Calculation (Using Real Derivatives)')
indices = AlgoConfig.fetch[:indices] || []
nifty_index = indices.find { |idx| ['NIFTY', :NIFTY].include?(idx[:key]) } || {}
index_cfg = nifty_index[:config] || nifty_index || {}

if index_cfg.any? || nifty_index.any?
  # Setup test derivatives if needed
  ServiceTestHelper.setup_test_derivatives

  # Get spot price (ATM) for NIFTY
  spot_price = ServiceTestHelper.fetch_ltp(segment: 'IDX_I', security_id: '13')
  unless spot_price&.positive?
    ServiceTestHelper.print_warning('Could not fetch NIFTY spot price - using fallback')
    spot_price = 26_000.0
  end

  ServiceTestHelper.print_info("NIFTY Spot Price (ATM): ₹#{spot_price.round(2)}")

  # Find nearest expiry
  nifty_instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')
  expiry_date = nil
  if nifty_instrument&.expiry_list&.any?
    today = Date.today
    parsed_expiries = nifty_instrument.expiry_list.compact.filter_map do |raw|
      case raw
      when Date then raw
      when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
      when String then begin
        Date.parse(raw)
      rescue StandardError
        nil
      end
      end
    end
    next_expiry = parsed_expiries.select { |date| date >= today }.min
    expiry_date = next_expiry if next_expiry
  end

  unless expiry_date
    ServiceTestHelper.print_warning('Could not find expiry date - using test derivatives')
    expiry_date = Date.today + 7.days
  end

  ServiceTestHelper.print_info("Expiry Date: #{expiry_date}")

  # Find ATM or 2 OTM options (CE for bullish)
  # Calculate strike interval (typically 50 for NIFTY)
  strike_interval = 50
  atm_strike = (spot_price / strike_interval).round * strike_interval
  target_strikes = [atm_strike, atm_strike + strike_interval, atm_strike + (2 * strike_interval)] # ATM, ATM+1, ATM+2

  ServiceTestHelper.print_info("Target Strikes: #{target_strikes.map do |s|
    offset = (s - atm_strike) / strike_interval
    offset == 0 ? "#{s} (ATM)" : "#{s} (ATM+#{offset.to_i})"
  end.join(', ')}")

  # Find derivatives for these strikes (prefer ATM, then ATM+1, then ATM+2)
  derivatives = Derivative.where(
    underlying_symbol: 'NIFTY',
    expiry_date: expiry_date,
    option_type: 'CE'
  ).where(strike_price: target_strikes).order(
    Arel.sql("CASE
      WHEN strike_price = #{atm_strike} THEN 1
      WHEN strike_price = #{atm_strike + strike_interval} THEN 2
      WHEN strike_price = #{atm_strike + (2 * strike_interval)} THEN 3
      ELSE 4
    END")
  ).limit(3)

  if derivatives.empty?
    ServiceTestHelper.print_warning('No derivatives found - using fallback option price')
    test_entry_price = 150.0
    test_lot_size = 75
    test_scale = 1
    source = 'fallback (no derivatives in DB)'
  else
    # Get LTP for the first available derivative (prefer ATM, then ATM+1, then ATM+2)
    test_derivative = derivatives.first
    test_lot_size = test_derivative.lot_size || 75

    # Try to get LTP from tick cache or API
    seg = test_derivative.exchange_segment || 'NSE_FNO'
    sid = test_derivative.security_id

    ltp = Live::TickCache.ltp(seg, sid) if seg && sid
    unless ltp&.positive?
      ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s, suppress_rate_limit_warning: true)
    end

    if ltp&.positive?
      test_entry_price = ltp
      source = 'API/TickCache'
    else
      test_entry_price = 150.0
      source = 'fallback (no LTP available)'
    end

    test_scale = 1

    ServiceTestHelper.print_success("Found derivative: #{test_derivative.symbol_name || 'NIFTY'} #{test_derivative.strike_price} CE")
    ServiceTestHelper.print_info("  Strike: #{test_derivative.strike_price}")
    ServiceTestHelper.print_info("  Lot Size: #{test_lot_size}")
    ServiceTestHelper.print_info("  LTP: ₹#{test_entry_price.round(2)} (#{source})")
  end

  # Calculate cost per lot for reference
  cost_per_lot = test_entry_price * test_lot_size
  ServiceTestHelper.print_info("  Cost per Lot: ₹#{cost_per_lot.round(2)} (#{test_entry_price.round(2)} × #{test_lot_size})")

  quantity = Capital::Allocator.qty_for(
    index_cfg: index_cfg,
    entry_price: test_entry_price,
    derivative_lot_size: test_lot_size,
    scale_multiplier: test_scale
  )

  ServiceTestHelper.print_info('Index: NIFTY')
  ServiceTestHelper.print_info("  Entry Price: ₹#{test_entry_price.round(2)} (option price from #{source})")
  ServiceTestHelper.print_info("  Lot Size: #{test_lot_size}")
  ServiceTestHelper.print_info("  Scale: #{test_scale}")
  ServiceTestHelper.print_info("  Calculated Quantity: #{quantity}")

  if quantity > 0
    total_cost = test_entry_price * quantity
    lots = quantity / test_lot_size
    ServiceTestHelper.print_success('  ✅ Quantity calculated successfully')
    ServiceTestHelper.print_info("  Total Cost: ₹#{total_cost.round(2)}")
    ServiceTestHelper.print_info("  Lots: #{lots} (#{quantity} shares)")
  else
    # Explain why quantity is 0
    min_lot_cost = test_entry_price * test_lot_size
    allocation = available_cash * (index_cfg[:capital_alloc_pct] || 0.25)
    ServiceTestHelper.print_warning('  ⚠️  Quantity is 0')
    ServiceTestHelper.print_info("  Reason: Minimum lot cost (₹#{min_lot_cost.round(2)}) exceeds available allocation (₹#{allocation.round(2)})")
    ServiceTestHelper.print_info('  This is correct behavior - insufficient capital for minimum lot')
  end
else
  ServiceTestHelper.print_warning('NIFTY index config not found in algo.yml')
end

# Test 4: Deployment policy
ServiceTestHelper.print_section('4. Deployment Policy')
test_balances = [50_000, 100_000, 200_000, 500_000]

test_balances.each do |balance|
  policy = Capital::Allocator.deployment_policy(balance)
  ServiceTestHelper.print_info("Balance: ₹#{balance}")
  ServiceTestHelper.print_info("  Allocation %: #{(policy[:alloc_pct] * 100).round(2)}%")
  ServiceTestHelper.print_info("  Risk per trade %: #{(policy[:risk_per_trade_pct] * 100).round(2)}%")
  ServiceTestHelper.print_info("  Daily max loss %: #{(policy[:daily_max_loss_pct] * 100).round(2)}%")
end

# Test 5: Test with different scale multipliers (using same derivative)
ServiceTestHelper.print_section('5. Scale Multiplier Test')
if index_cfg.any? && defined?(test_entry_price) && defined?(test_lot_size)
  [1, 2, 3].each do |scale|
    quantity = Capital::Allocator.qty_for(
      index_cfg: index_cfg,
      entry_price: test_entry_price,
      derivative_lot_size: test_lot_size,
      scale_multiplier: scale
    )
    if quantity > 0
      total_cost = test_entry_price * quantity
      lots = quantity / test_lot_size
      ServiceTestHelper.print_success("Scale #{scale}: Quantity = #{quantity} (#{lots} lots, Cost: ₹#{total_cost.round(2)})")
    else
      ServiceTestHelper.print_info("Scale #{scale}: Quantity = #{quantity} (insufficient capital)")
    end
  end
else
  ServiceTestHelper.print_warning('Skipping scale multiplier test - derivative data not available')
end

ServiceTestHelper.print_success('Capital::Allocator test completed')
