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

# Test 3: Test quantity calculation using actual derivatives (ATM from StrikeSelector)
ServiceTestHelper.print_section('3. Quantity Calculation (Using Real Derivatives from API)')
indices = AlgoConfig.fetch[:indices] || []
nifty_index = indices.find { |idx| ['NIFTY', :NIFTY].include?(idx[:key]) } || {}
index_cfg = nifty_index[:config] || nifty_index || {}

if index_cfg.any? || nifty_index.any?
  # Setup test derivatives if needed
  ServiceTestHelper.setup_test_derivatives

  # Use StrikeSelector to find ATM derivative (same as production)
  ServiceTestHelper.print_info('Finding ATM derivative using StrikeSelector...')
  strike_selector = Options::StrikeSelector.new

  # Debug: Check prerequisites
  spot_price = ServiceTestHelper.fetch_ltp(segment: 'IDX_I', security_id: '13')
  ServiceTestHelper.print_info("NIFTY spot price: #{spot_price ? "₹#{spot_price}" : 'nil'}")

  # Check if derivatives exist
  nifty_instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')
  if nifty_instrument
    derivatives_count = nifty_instrument.derivatives.where(option_type: 'CE').count
    ServiceTestHelper.print_info("NIFTY CE derivatives in DB: #{derivatives_count}")
  end

  instrument_hash = strike_selector.select(
    index_key: 'NIFTY',
    direction: :bullish,
    expiry: nil, # Auto-select nearest expiry
    trend_score: nil # Use default (ATM only)
  )

  if instrument_hash.nil?
    ServiceTestHelper.print_warning('StrikeSelector returned nil - checking logs for reason...')
    # The reason should be in Rails.logger, but we can't access it easily in test
    # Common reasons: no spot price, no candidates, no valid strikes
  end

  test_derivative = nil
  test_entry_price = nil
  test_lot_size = nil
  test_scale = 1
  source = nil

  if instrument_hash
    # Found via StrikeSelector
    ServiceTestHelper.print_success("Found derivative via StrikeSelector: #{instrument_hash[:symbol]}")

    # Map exchange_segment to segment for derivative lookup
    seg = instrument_hash[:exchange_segment] || instrument_hash[:segment] || 'NSE_FNO'

    # Find the derivative
    test_derivative = Derivative.find_by(
      segment: 'derivatives', # Derivatives use 'derivatives' as segment
      security_id: instrument_hash[:security_id]
    ) || Derivative.find_by(symbol_name: instrument_hash[:symbol])

    if test_derivative
      test_lot_size = instrument_hash[:lot_size] || test_derivative.lot_size || 75

      # Get LTP using the SAME method as production (derivative.ltp() from InstrumentHelpers)
      # This matches how EntryManager gets LTP

      # 1. Try derivative.ltp() method (InstrumentHelpers - handles WebSocket + API)
      ltp = test_derivative.ltp&.to_f
      source = 'derivative.ltp()' if ltp&.positive?
      ServiceTestHelper.print_info("Got LTP from derivative.ltp(): ₹#{ltp}") if ltp&.positive?

      # 2. Try from instrument_hash (if StrikeSelector provided it)
      unless ltp&.positive?
        ltp = instrument_hash[:ltp]&.to_f if instrument_hash[:ltp]&.positive?
        source = 'StrikeSelector' if ltp&.positive?
      end

      # 3. Try TickCache
      unless ltp&.positive?
        seg_for_cache = test_derivative.exchange_segment || seg
        sid_for_cache = instrument_hash[:security_id]
        ltp = Live::TickCache.ltp(seg_for_cache, sid_for_cache)&.to_f
        source = 'TickCache' if ltp&.positive?
        ServiceTestHelper.print_info("Got LTP from TickCache: ₹#{ltp}") if ltp&.positive?
      end

      # 4. Try RedisTickCache
      unless ltp&.positive?
        begin
          seg_for_redis = test_derivative.exchange_segment || seg
          sid_for_redis = instrument_hash[:security_id]
          tick_data = Live::RedisTickCache.instance.fetch_tick(seg_for_redis, sid_for_redis)
          ltp = tick_data[:ltp]&.to_f if tick_data && tick_data[:ltp]&.to_f&.positive?
          source = 'RedisTickCache' if ltp&.positive?
          ServiceTestHelper.print_info("Got LTP from RedisTickCache: ₹#{ltp}") if ltp&.positive?
        rescue StandardError => e
          ServiceTestHelper.print_warning("RedisTickCache error: #{e.message}")
        end
      end

      # 5. Try tradable's fetch_ltp_from_api_for_segment()
      unless ltp&.positive?
        begin
          seg_for_api = test_derivative.exchange_segment || seg
          sid_for_api = instrument_hash[:security_id]
          ltp = test_derivative.fetch_ltp_from_api_for_segment(segment: seg_for_api, security_id: sid_for_api)&.to_f
          source = 'fetch_ltp_from_api_for_segment()' if ltp&.positive?
          ServiceTestHelper.print_info("Got LTP from fetch_ltp_from_api_for_segment(): ₹#{ltp}") if ltp&.positive?
        rescue StandardError => e
          ServiceTestHelper.print_warning("fetch_ltp_from_api_for_segment error: #{e.message}")
        end
      end

      # 6. Last resort: Direct API call
      unless ltp&.positive?
        seg_for_api = test_derivative.exchange_segment || seg
        sid_for_api = instrument_hash[:security_id]
        ltp = ServiceTestHelper.fetch_ltp(segment: seg_for_api, security_id: sid_for_api.to_s,
                                          suppress_rate_limit_warning: true)
        source = 'Direct API' if ltp&.positive?
        ServiceTestHelper.print_info("Got LTP from Direct API: ₹#{ltp}") if ltp&.positive?
      end

      if ltp&.positive?
        test_entry_price = ltp
        ServiceTestHelper.print_success("Found derivative: #{test_derivative.symbol_name || 'NIFTY'} #{test_derivative.strike_price} CE")
        ServiceTestHelper.print_info("  Strike: ₹#{test_derivative.strike_price}")
        ServiceTestHelper.print_info("  Expiry: #{test_derivative.expiry_date}")
        ServiceTestHelper.print_info("  Lot Size: #{test_lot_size}")
        ServiceTestHelper.print_info("  LTP: ₹#{test_entry_price.round(2)} (from #{source})")
      else
        ServiceTestHelper.print_warning('Could not fetch LTP for derivative - using fallback')
        test_entry_price = 150.0
        source = 'fallback (no LTP available)'
      end
    else
      ServiceTestHelper.print_warning("Derivative not found in DB for #{instrument_hash[:symbol]} - using fallback")
      test_entry_price = 150.0
      test_lot_size = instrument_hash[:lot_size] || 75
      source = 'fallback (derivative not in DB)'
    end
  else
    # Fallback: Use find_atm_or_otm_derivative helper
    ServiceTestHelper.print_warning('StrikeSelector returned nil - trying fallback method...')
    test_derivative = ServiceTestHelper.find_atm_or_otm_derivative(
      underlying_symbol: 'NIFTY',
      option_type: 'CE',
      preference: :atm
    )

    if test_derivative
      test_lot_size = test_derivative.lot_size || 75

      # Get LTP using derivative.ltp() method
      ltp = test_derivative.ltp&.to_f
      if ltp&.positive?
        test_entry_price = ltp
        source = 'derivative.ltp() (fallback)'
        ServiceTestHelper.print_success("Found derivative via fallback: #{test_derivative.symbol_name}")
        ServiceTestHelper.print_info("  Strike: ₹#{test_derivative.strike_price}")
        ServiceTestHelper.print_info("  Lot Size: #{test_lot_size}")
        ServiceTestHelper.print_info("  LTP: ₹#{test_entry_price.round(2)} (from #{source})")
      else
        ServiceTestHelper.print_warning('Could not get LTP from derivative.ltp() - using fallback')
        test_entry_price = 150.0
        source = 'fallback (no LTP)'
      end
    else
      ServiceTestHelper.print_warning('No derivatives found - using fallback option price')
      test_entry_price = 150.0
      test_lot_size = 75
      source = 'fallback (no derivatives)'
    end
  end

  # Calculate cost per lot for reference
  cost_per_lot = test_entry_price * test_lot_size
  ServiceTestHelper.print_info("  Cost per Lot: ₹#{cost_per_lot.round(2)} (#{test_entry_price.round(2)} × #{test_lot_size})")

  # Calculate quantity using Capital::Allocator (same as production)
  ServiceTestHelper.print_info('')
  ServiceTestHelper.print_info('Calculating quantity using Capital::Allocator...')
  quantity = Capital::Allocator.qty_for(
    index_cfg: index_cfg,
    entry_price: test_entry_price,
    derivative_lot_size: test_lot_size,
    scale_multiplier: test_scale
  )

  ServiceTestHelper.print_info('Index: NIFTY')
  ServiceTestHelper.print_info("  Entry Price: ₹#{test_entry_price.round(2)} (from #{source})")
  ServiceTestHelper.print_info("  Lot Size: #{test_lot_size}")
  ServiceTestHelper.print_info("  Scale: #{test_scale}")
  ServiceTestHelper.print_info("  Available Cash: ₹#{available_cash.round(2)}")
  ServiceTestHelper.print_info("  Calculated Quantity: #{quantity}")

  if quantity.positive?
    total_cost = test_entry_price * quantity
    lots = quantity / test_lot_size
    ServiceTestHelper.print_success('  ✅ Quantity calculated successfully')
    ServiceTestHelper.print_info("  Total Cost: ₹#{total_cost.round(2)}")
    ServiceTestHelper.print_info("  Lots: #{lots.round(2)} (#{quantity} shares)")

    # Verify quantity is multiple of lot size
    if (quantity % test_lot_size).zero?
      ServiceTestHelper.print_success("  ✅ Quantity is multiple of lot size (#{test_lot_size})")
    else
      ServiceTestHelper.print_warning("  ⚠️  Quantity (#{quantity}) is NOT multiple of lot size (#{test_lot_size})")
    end
  else
    # Explain why quantity is 0
    min_lot_cost = test_entry_price * test_lot_size
    policy = Capital::Allocator.deployment_policy(available_cash)
    allocation = available_cash * (index_cfg[:capital_alloc_pct] || policy[:alloc_pct])
    ServiceTestHelper.print_warning('  ⚠️  Quantity is 0')
    ServiceTestHelper.print_info("  Reason: Minimum lot cost (₹#{min_lot_cost.round(2)}) exceeds available allocation (₹#{allocation.round(2)})")
    ServiceTestHelper.print_info("  Available Cash: ₹#{available_cash.round(2)}")
    ServiceTestHelper.print_info("  Allocation %: #{(index_cfg[:capital_alloc_pct] || policy[:alloc_pct]) * 100}%")
    ServiceTestHelper.print_info("  Allocation Amount: ₹#{allocation.round(2)}")
    ServiceTestHelper.print_info("  Min Lot Cost: ₹#{min_lot_cost.round(2)}")
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
if index_cfg.any? && test_entry_price && test_lot_size
  ServiceTestHelper.print_info("Testing with entry price: ₹#{test_entry_price.round(2)}, lot size: #{test_lot_size}")
  [1, 2, 3].each do |scale|
    quantity = Capital::Allocator.qty_for(
      index_cfg: index_cfg,
      entry_price: test_entry_price,
      derivative_lot_size: test_lot_size,
      scale_multiplier: scale
    )
    if quantity.positive?
      total_cost = test_entry_price * quantity
      lots = quantity.to_f / test_lot_size
      ServiceTestHelper.print_success("Scale #{scale}: Quantity = #{quantity} (#{lots.round(2)} lots, Cost: ₹#{total_cost.round(2)})")

      # Verify quantity is multiple of lot size
      if (quantity % test_lot_size).zero?
        ServiceTestHelper.print_info('  ✅ Valid: Multiple of lot size')
      else
        ServiceTestHelper.print_warning('  ⚠️  Invalid: NOT multiple of lot size')
      end
    else
      ServiceTestHelper.print_info("Scale #{scale}: Quantity = #{quantity} (insufficient capital)")
    end
  end
else
  ServiceTestHelper.print_warning('Skipping scale multiplier test - derivative data not available')
end

# Test 6: Test with multiple indices (if available)
ServiceTestHelper.print_section('6. Multiple Indices Test')
indices_to_test = %w[NIFTY BANKNIFTY].select do |index_key|
  idx = indices.find { |i| [index_key, index_key.to_sym].include?(i[:key]) }
  idx && (idx[:config] || idx).any?
end

if indices_to_test.any?
  indices_to_test.each do |index_key|
    ServiceTestHelper.print_info("Testing #{index_key}...")
    idx = indices.find { |i| [index_key, index_key.to_sym].include?(i[:key]) }
    idx_cfg = idx[:config] || idx || {}

    # Debug: Check prerequisites for StrikeSelector
    ServiceTestHelper.print_info("  Checking prerequisites for #{index_key}...")

    # 1. Check AlgoConfig
    algo_cfg = AlgoConfig.fetch[:indices]&.find { |i| i[:key].to_s.upcase == index_key.to_s.upcase }
    if algo_cfg.nil?
      ServiceTestHelper.print_warning("  ❌ AlgoConfig missing for #{index_key}")
      next
    end
    ServiceTestHelper.print_info("  ✅ AlgoConfig found: segment=#{algo_cfg[:segment]}, sid=#{algo_cfg[:sid]}")

    # 2. Check spot price
    spot_seg = algo_cfg[:segment]
    spot_sid = algo_cfg[:sid]
    spot_from_tick = Live::TickCache.ltp(spot_seg, spot_sid)
    spot_from_redis = Live::RedisTickCache.instance.fetch_tick(spot_seg, spot_sid)&.dig(:ltp)&.to_f
    spot_price = spot_from_tick || spot_from_redis
    if spot_price&.positive?
      ServiceTestHelper.print_info("  ✅ Spot price: ₹#{spot_price} (from #{spot_from_tick ? 'TickCache' : 'RedisTickCache'})")
    else
      ServiceTestHelper.print_warning("  ❌ No spot price available (TickCache=#{spot_from_tick}, Redis=#{spot_from_redis})")
      # Try API fallback
      spot_price = ServiceTestHelper.fetch_ltp(segment: spot_seg, security_id: spot_sid.to_s,
                                               suppress_rate_limit_warning: true)
      if spot_price&.positive?
        ServiceTestHelper.print_info("  ✅ Spot price from API: ₹#{spot_price}")
      else
        ServiceTestHelper.print_warning('  ❌ Could not fetch spot price from API')
        next
      end
    end

    # 3. Check if derivatives exist in DB
    instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: spot_sid.to_s)
    if instrument.nil?
      ServiceTestHelper.print_warning('  ❌ Index instrument not found in DB')
      next
    end

    # Check expiry list
    expiry_list = instrument.expiry_list
    if expiry_list.blank?
      ServiceTestHelper.print_warning("  ❌ No expiry list for #{index_key}")
      next
    end
    ServiceTestHelper.print_info("  ✅ Expiry list: #{expiry_list.first(3).join(', ')}")

    # Check derivatives for nearest expiry
    nearest_expiry = expiry_list.first
    derivatives_count = Derivative.where(
      underlying_symbol: index_key,
      expiry_date: nearest_expiry.is_a?(Date) ? nearest_expiry : Date.parse(nearest_expiry.to_s)
    ).where.not(option_type: [nil, '']).count
    if derivatives_count.zero?
      ServiceTestHelper.print_warning("  ❌ No derivatives found for #{index_key} expiry #{nearest_expiry}")
      next
    end
    ServiceTestHelper.print_info("  ✅ Found #{derivatives_count} derivatives for nearest expiry")

    # 4. Test DerivativeChainAnalyzer directly
    ServiceTestHelper.print_info('  Testing DerivativeChainAnalyzer directly...')
    begin
      analyzer = Options::DerivativeChainAnalyzer.new(
        index_key: index_key,
        expiry: nil,
        config: {}
      )
      candidates = analyzer.select_candidates(limit: 5, direction: :bullish)
      if candidates.empty?
        ServiceTestHelper.print_warning('  ❌ DerivativeChainAnalyzer returned no candidates')
        ServiceTestHelper.print_info('  This usually means:')
        ServiceTestHelper.print_info('    - No spot price available')
        ServiceTestHelper.print_info('    - No expiry found')
        ServiceTestHelper.print_info('    - No derivatives in DB for that expiry')
        ServiceTestHelper.print_info('    - API chain fetch failed (fetch_option_chain returned nil)')
      else
        ServiceTestHelper.print_info("  ✅ DerivativeChainAnalyzer found #{candidates.count} candidates")
        ServiceTestHelper.print_info("    Top candidate: Strike=#{candidates.first[:strike]}, Type=#{candidates.first[:type]}, LTP=#{candidates.first[:ltp]}")
      end
    rescue StandardError => e
      ServiceTestHelper.print_warning("  ❌ DerivativeChainAnalyzer error: #{e.class} - #{e.message}")
    end

    # 5. Try StrikeSelector
    ServiceTestHelper.print_info('  Calling StrikeSelector.select()...')
    strike_selector = Options::StrikeSelector.new
    inst_hash = strike_selector.select(
      index_key: index_key,
      direction: :bullish,
      expiry: nil,
      trend_score: nil
    )

    if inst_hash.nil?
      ServiceTestHelper.print_warning('  ❌ StrikeSelector returned nil')
      ServiceTestHelper.print_info('  Common reasons:')
      ServiceTestHelper.print_info('    - No spot price (already checked above)')
      ServiceTestHelper.print_info('    - No candidates from DerivativeChainAnalyzer (checked above)')
      ServiceTestHelper.print_info("    - Candidates don't match allowed strike distance (ATM only with trend_score=nil)")
      ServiceTestHelper.print_info('    - Candidates fail validation (liquidity/spread/premium)')
      next
    end

    ServiceTestHelper.print_info("  ✅ StrikeSelector found derivative: #{inst_hash[:symbol] || inst_hash[:security_id]}")

    entry = nil
    lot_size = nil
    derivative = nil

    if inst_hash
      # Found via StrikeSelector - find the derivative
      seg = inst_hash[:exchange_segment] || inst_hash[:segment] || 'NSE_FNO'
      derivative = Derivative.find_by(
        segment: 'derivatives',
        security_id: inst_hash[:security_id]
      ) || Derivative.find_by(symbol_name: inst_hash[:symbol])

      if derivative
        lot_size = inst_hash[:lot_size] || derivative.lot_size || 50

        # Get LTP using same method as Test 3
        # 1. Try derivative.ltp()
        entry = derivative.ltp&.to_f
        ServiceTestHelper.print_info("  Got LTP from derivative.ltp(): ₹#{entry}") if entry&.positive?

        # 2. Try from instrument_hash
        entry = inst_hash[:ltp]&.to_f if !entry&.positive? && inst_hash[:ltp]&.positive?

        # 3. Try TickCache
        unless entry&.positive?
          seg_for_cache = derivative.exchange_segment || seg
          sid_for_cache = inst_hash[:security_id]
          entry = Live::TickCache.ltp(seg_for_cache, sid_for_cache)&.to_f
        end

        # 4. Try RedisTickCache
        unless entry&.positive?
          begin
            seg_for_redis = derivative.exchange_segment || seg
            sid_for_redis = inst_hash[:security_id]
            tick_data = Live::RedisTickCache.instance.fetch_tick(seg_for_redis, sid_for_redis)
            entry = tick_data[:ltp]&.to_f if tick_data && tick_data[:ltp]&.to_f&.positive?
          rescue StandardError => e
            ServiceTestHelper.print_warning("  RedisTickCache error: #{e.message}")
          end
        end

        # 5. Try fetch_ltp_from_api_for_segment()
        unless entry&.positive?
          begin
            seg_for_api = derivative.exchange_segment || seg
            sid_for_api = inst_hash[:security_id]
            entry = derivative.fetch_ltp_from_api_for_segment(segment: seg_for_api, security_id: sid_for_api)&.to_f
          rescue StandardError => e
            ServiceTestHelper.print_warning("  fetch_ltp_from_api_for_segment error: #{e.message}")
          end
        end

        # 6. Last resort: Direct API
        unless entry&.positive?
          seg_for_api = derivative.exchange_segment || seg
          sid_for_api = inst_hash[:security_id]
          entry = ServiceTestHelper.fetch_ltp(segment: seg_for_api, security_id: sid_for_api.to_s,
                                              suppress_rate_limit_warning: true)
        end
      end
    end

    # Fallback: Use find_atm_or_otm_derivative if StrikeSelector failed
    unless entry&.positive? && derivative
      ServiceTestHelper.print_info("  StrikeSelector failed for #{index_key}, trying fallback...")
      derivative = ServiceTestHelper.find_atm_or_otm_derivative(
        underlying_symbol: index_key,
        option_type: 'CE',
        preference: :atm
      )

      if derivative
        lot_size = derivative.lot_size || 50
        entry = derivative.ltp&.to_f
        ServiceTestHelper.print_info("  Got LTP from fallback derivative.ltp(): ₹#{entry}") if entry&.positive?
      end
    end

    if entry&.positive? && lot_size
      qty = Capital::Allocator.qty_for(
        index_cfg: idx_cfg,
        entry_price: entry,
        derivative_lot_size: lot_size,
        scale_multiplier: 1
      )

      if qty.positive?
        total_cost = entry * qty
        lots = qty.to_f / lot_size
        ServiceTestHelper.print_success("  #{index_key}: Quantity = #{qty} (#{lots.round(2)} lots, Entry: ₹#{entry.round(2)}, Lot: #{lot_size}, Cost: ₹#{total_cost.round(2)})")
      else
        min_lot_cost = entry * lot_size
        policy = Capital::Allocator.deployment_policy(available_cash)
        allocation = available_cash * (idx_cfg[:capital_alloc_pct] || policy[:alloc_pct])
        ServiceTestHelper.print_info("  #{index_key}: Quantity = 0 (insufficient capital - min lot: ₹#{min_lot_cost.round(2)}, allocation: ₹#{allocation.round(2)})")
      end
    else
      ServiceTestHelper.print_warning("  #{index_key}: Could not find derivative or LTP")
      if derivative
        ServiceTestHelper.print_info("    Derivative found: #{derivative.symbol_name}, but LTP unavailable")
      else
        ServiceTestHelper.print_info('    No derivative found in database')
      end
    end
  end
else
  ServiceTestHelper.print_info('Only NIFTY available for testing')
end

ServiceTestHelper.print_success('Capital::Allocator test completed')
