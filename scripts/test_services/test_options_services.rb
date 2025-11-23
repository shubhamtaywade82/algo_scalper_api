#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Options Services Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_instruments
ServiceTestHelper.setup_test_derivatives

# Test 1: Options::StrikeSelector
ServiceTestHelper.print_section('1. Options::StrikeSelector')
strike_selector = Options::StrikeSelector.new
ServiceTestHelper.print_success('StrikeSelector initialized')

# Test 2: Test strike selection
ServiceTestHelper.print_section('2. Strike Selection Test')
index_key = :NIFTY
direction = :bullish

begin
  result = strike_selector.select(
    index_key: index_key,
    direction: direction
  )

  if result
    ServiceTestHelper.print_success('Strike selection completed')
    ServiceTestHelper.print_info("Result:\n#{ServiceTestHelper.format_hash(result)}")
  else
    ServiceTestHelper.print_info('No strike selected (this is expected - requires live market data and derivatives meeting criteria)')
  end
rescue StandardError => e
  ServiceTestHelper.print_error("Strike selection failed: #{e.class} - #{e.message}")
end

# Test 3: Index Rules
ServiceTestHelper.print_section('3. Index Rules')
index_rules = [
  Options::IndexRules::Nifty,
  Options::IndexRules::Banknifty,
  Options::IndexRules::Sensex
]

index_rules.each do |rule_class|
  rule = rule_class.new
  ServiceTestHelper.print_info("\n#{rule_class.name}:")
  ServiceTestHelper.print_info("  Min Volume: #{rule_class::MIN_VOLUME}")
  ServiceTestHelper.print_info("  Min Premium: ₹#{rule_class::MIN_PREMIUM}")
  ServiceTestHelper.print_info("  Max Spread %: #{rule_class::MAX_SPREAD_PCT * 100}%")
  ServiceTestHelper.print_info("  Lot Size: #{rule.lot_size}")
  ServiceTestHelper.print_info("  Multiplier: #{rule.multiplier}")
end

# Test 4: DerivativeChainAnalyzer (if exists)
ServiceTestHelper.print_section('4. DerivativeChainAnalyzer')
begin
  # Get actual expiry from option chain
  nifty_instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')
  expiry_date = nil
  if nifty_instrument
    begin
      chain_data = nifty_instrument.fetch_option_chain
      if chain_data && nifty_instrument.expiry_list&.any?
        today = Date.today
        parsed_expiries = nifty_instrument.expiry_list.compact.filter_map do |raw|
          case raw
          when Date then raw
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          when String then Date.parse(raw) rescue nil
          end
        end
        expiry_date = parsed_expiries.select { |date| date >= today }.min
        ServiceTestHelper.print_info("Using expiry from option chain: #{expiry_date}")
      end
    rescue StandardError => e
      ServiceTestHelper.print_warning("Could not get expiry from option chain: #{e.message}")
    end
  end
  expiry_date ||= Date.today + 7.days

  # Use lenient config for testing (lower thresholds)
  test_config = {
    min_oi: 1000,  # Lower than default 10,000
    min_iv: 1.0,  # Lower than default 5.0
    max_iv: 100.0, # Higher than default 60.0
    max_spread_pct: 0.10, # 10% instead of default 3%
    strike_distance_pct: 0.05 # 5% instead of default 2%
  }

  analyzer = Options::DerivativeChainAnalyzer.new(
    index_key: index_key,
    expiry: expiry_date,
    config: test_config
  )
  ServiceTestHelper.print_success('DerivativeChainAnalyzer initialized')
  ServiceTestHelper.print_info("Test config: min_oi=#{test_config[:min_oi]}, min_iv=#{test_config[:min_iv]}, max_spread=#{test_config[:max_spread_pct] * 100}%")

  # Test candidate selection
  candidates = analyzer.select_candidates(limit: 5, direction: :bullish)
  if candidates.any?
    ServiceTestHelper.print_success("Found #{candidates.size} candidates")
    candidates.first(5).each do |candidate|
      ServiceTestHelper.print_info("  Strike: #{candidate[:strike]}, Type: #{candidate[:type]}, Score: #{candidate[:score]&.round(3)}")
      ServiceTestHelper.print_info("    LTP: ₹#{candidate[:ltp]&.round(2)}, OI: #{candidate[:oi]}, IV: #{candidate[:iv]&.round(2)}%")
      ServiceTestHelper.print_info("    Reason: #{candidate[:reason]}")
    end
  else
    ServiceTestHelper.print_warning('No candidates found')
    ServiceTestHelper.print_info('Note: DerivativeChainAnalyzer fetches option chain from DhanHQ API using Instrument#fetch_option_chain')
    ServiceTestHelper.print_info('However, it requires derivatives in the database to match the API chain data.')
    ServiceTestHelper.print_info('Possible reasons for no candidates:')
    ServiceTestHelper.print_info('  - Test derivatives (with synthetic security IDs) don\'t match API chain data')
    ServiceTestHelper.print_info('  - Strike string format mismatch between derivatives and API chain')
    ServiceTestHelper.print_info('  - No spot LTP available (check TickCache/RedisTickCache)')
    ServiceTestHelper.print_info('  - No derivatives in database for this expiry')
    ServiceTestHelper.print_info('  - Option chain API returned no data')
    ServiceTestHelper.print_info('  - All options filtered out by criteria (OI, IV, spread, strike distance)')

    # Debug: Check what's available
    spot = analyzer.send(:spot_ltp)
    if spot&.positive?
      ServiceTestHelper.print_info("  ✓ Spot LTP available: ₹#{spot.round(2)}")
    else
      ServiceTestHelper.print_warning("  ✗ Spot LTP not available")
      # Try to fetch from API
      begin
        nifty_instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')
        if nifty_instrument
          api_spot = nifty_instrument.ltp&.to_f
          if api_spot&.positive?
            ServiceTestHelper.print_info("  ✓ Fetched spot LTP from API: ₹#{api_spot.round(2)}")
            # Note: This won't update the analyzer's internal spot, but shows it's available
          else
            ServiceTestHelper.print_warning("  ✗ Could not fetch spot LTP from API either")
          end
        end
      rescue StandardError => e
        ServiceTestHelper.print_warning("  ✗ Error fetching spot from API: #{e.message}")
      end
    end

    expiry = analyzer.send(:find_nearest_expiry)
    if expiry
      ServiceTestHelper.print_info("  ✓ Nearest expiry found: #{expiry}")
      chain = analyzer.send(:load_chain_for_expiry, expiry)
      ServiceTestHelper.print_info("  ✓ Chain loaded: #{chain.size} options")
      if chain.any?
        # Show sample options with their data
        ce_options = chain.select { |o| o[:type] == 'CE' }.first(3)
        pe_options = chain.select { |o| o[:type] == 'PE' }.first(3)

        ServiceTestHelper.print_info("  Sample CE options:")
        ce_options.first(3).each do |opt|
          derivative = opt[:derivative]
          is_test = derivative&.security_id.to_s.start_with?('TEST_')
          test_marker = is_test ? ' [TEST]' : ''

          ServiceTestHelper.print_info("    Strike=#{opt[:strike]}, OI=#{opt[:oi] || 'nil'}, IV=#{opt[:iv] || 'nil'}%, LTP=₹#{opt[:ltp] || 'nil'}, Bid=₹#{opt[:bid] || 'nil'}, Ask=₹#{opt[:ask] || 'nil'}#{test_marker}")
          ServiceTestHelper.print_info("      Derivative ID: #{derivative&.id}, Security ID: #{derivative&.security_id}, Strike: #{derivative&.strike_price}, Expiry: #{derivative&.expiry_date}")

          # Debug: Check API chain data directly
          api_chain = analyzer.send(:fetch_api_chain, expiry)

          if api_chain
            # Try different strike string formats (matching DerivativeChainAnalyzer logic)
            strike_float = opt[:strike].to_f
            strike_formats = [
              sprintf('%.6f', strike_float), # "27950.000000" - API format
              strike_float.to_s,              # "27950.0" - default float format
              strike_float.to_i.to_s,         # "27950" - integer format
              sprintf('%.2f', strike_float)   # "27950.00" - 2 decimal places
            ].uniq

            api_ce = nil
            api_pe = nil
            strike_formats.each do |strike_str|
              api_ce ||= api_chain.dig(strike_str, 'ce')
              api_pe ||= api_chain.dig(strike_str, 'pe')
              break if api_ce && api_pe
            end

            ServiceTestHelper.print_info("      API chain lookup for strike #{opt[:strike]}:")
            ServiceTestHelper.print_info("        Tried formats: #{strike_formats.map { |f| "'#{f}'" }.join(', ')}")
            ServiceTestHelper.print_info("        CE found: #{api_ce ? 'YES' : 'NO'}")
            ServiceTestHelper.print_info("        PE found: #{api_pe ? 'YES' : 'NO'}")

            if api_ce
              ServiceTestHelper.print_success("        ✓ CE OI: #{api_ce['oi']}, IV: #{api_ce['implied_volatility']}%, LTP: ₹#{api_ce['last_price']}")
            else
              # Show what strikes ARE available in the API chain
              available_strikes = api_chain.keys.map(&:to_f).sort
              min_strike = available_strikes.first
              max_strike = available_strikes.last
              current_spot = analyzer.send(:spot_ltp) || ServiceTestHelper.fetch_ltp(segment: 'IDX_I', security_id: '13', suppress_rate_limit_warning: true) || 26_000.0
              atm_range = available_strikes.select { |s| (s - current_spot).abs <= current_spot * 0.02 }.first(5)

              ServiceTestHelper.print_warning("        ✗ CE not found for strike #{opt[:strike]}")
              ServiceTestHelper.print_info("        API chain has #{available_strikes.size} strikes")
              ServiceTestHelper.print_info("        Strike range: #{min_strike} - #{max_strike}")
              ServiceTestHelper.print_info("        Looking for ATM (~#{current_spot.round}), but API has strikes: #{available_strikes.first(10).join(', ')}...")
              if atm_range.any?
                ServiceTestHelper.print_info("        Near ATM strikes in API: #{atm_range.join(', ')}")
                ServiceTestHelper.print_warning("        ⚠️  Derivative strike #{opt[:strike]} doesn't match API chain strikes")
                ServiceTestHelper.print_info("        This is likely because:")
                ServiceTestHelper.print_info("          - Test derivative with synthetic strike#{is_test ? ' (TEST_ security ID)' : ''}")
                ServiceTestHelper.print_info("          - Derivative from different expiry than API chain")
                ServiceTestHelper.print_info("          - Strike format mismatch")
              else
                ServiceTestHelper.print_warning("        ⚠️  No strikes near current spot (#{current_spot.round}) in API chain")
                ServiceTestHelper.print_warning("        This suggests: expiry mismatch, stale data, or market closed")
              end
            end
          end
        end

        ServiceTestHelper.print_info("  Sample PE options:")
        pe_options.first(3).each do |opt|
          derivative = opt[:derivative]
          is_test = derivative&.security_id.to_s.start_with?('TEST_')
          test_marker = is_test ? ' [TEST]' : ''
          ServiceTestHelper.print_info("    Strike=#{opt[:strike]}, OI=#{opt[:oi] || 'nil'}, IV=#{opt[:iv] || 'nil'}%, LTP=₹#{opt[:ltp] || 'nil'}, Bid=₹#{opt[:bid] || 'nil'}, Ask=₹#{opt[:ask] || 'nil'}#{test_marker}")
          ServiceTestHelper.print_info("      Security ID: #{derivative&.security_id}, Expiry: #{derivative&.expiry_date}")
        end

        # Check why they're filtered (only if spot is available)
        if spot&.positive?
          atm = analyzer.send(:find_atm_strike, chain, spot)
          ServiceTestHelper.print_info("  ATM Strike: #{atm || 'nil (no spot available)'}")
        else
          ServiceTestHelper.print_warning("  Cannot calculate ATM strike - spot price not available")
        end

        ServiceTestHelper.print_info("  Filtering criteria:")
        ServiceTestHelper.print_info("    min_oi: #{test_config[:min_oi]} (options with OI < this are filtered)")
        ServiceTestHelper.print_info("    min_iv: #{test_config[:min_iv]}% (options with IV < this are filtered)")
        ServiceTestHelper.print_info("    max_spread: #{test_config[:max_spread_pct] * 100}% (options with spread > this are filtered)")

        # Count how many pass each filter
        ce_filtered = chain.select { |o| o[:type] == 'CE' }
        oi_passed = ce_filtered.count { |o| o[:oi].to_i >= test_config[:min_oi] }
        iv_passed = ce_filtered.count { |o| o[:iv].to_f >= test_config[:min_iv] && o[:iv].to_f <= test_config[:max_iv] }
        spread_passed = ce_filtered.count do |o|
          spread = analyzer.send(:calc_spread, o[:bid], o[:ask], o[:ltp])
          spread && spread <= test_config[:max_spread_pct]
        end

        ServiceTestHelper.print_info("  CE options filter results:")
        ServiceTestHelper.print_info("    Total CE: #{ce_filtered.size}")
        ServiceTestHelper.print_info("    Pass OI filter (>=#{test_config[:min_oi]}): #{oi_passed}")
        ServiceTestHelper.print_info("    Pass IV filter (#{test_config[:min_iv]}%-#{test_config[:max_iv]}%): #{iv_passed}")
        ServiceTestHelper.print_info("    Pass spread filter (<=#{test_config[:max_spread_pct] * 100}%): #{spread_passed}")
      end
    else
      ServiceTestHelper.print_warning("  ✗ No expiry found")
    end
  end
rescue NameError
  ServiceTestHelper.print_warning('DerivativeChainAnalyzer not found (may not be implemented yet)')
rescue StandardError => e
  ServiceTestHelper.print_error("DerivativeChainAnalyzer error: #{e.class} - #{e.message}")
  ServiceTestHelper.print_info("Backtrace: #{e.backtrace.first(3).join("\n")}")
end

# Test 5: Options data availability (ATM or 2 OTM only)
ServiceTestHelper.print_section('5. Options Data Availability (ATM or 2 OTM Only)')

# Get NIFTY instrument and fetch option chain
nifty_instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')
if nifty_instrument
  begin
    # Fetch option chain using Instrument#fetch_option_chain
    chain_data = nifty_instrument.fetch_option_chain
    if chain_data && chain_data[:oc]&.any?
      spot_price = chain_data[:last_price]&.to_f || ServiceTestHelper.fetch_ltp(segment: 'IDX_I', security_id: '13', suppress_rate_limit_warning: true) || 26_000.0

      # Get available strikes from option chain
      available_strikes = chain_data[:oc].keys.map(&:to_f).sort
      strike_interval = available_strikes.size >= 2 ? (available_strikes[1] - available_strikes[0]) : 50

      # Find ATM strike (closest to spot)
      atm_strike = available_strikes.min_by { |s| (s - spot_price).abs }

      # Calculate target strikes
      # For CE (bullish): ATM, ATM+1, ATM+2 (OTM calls)
      # For PE (bearish): ATM, ATM-1, ATM-2 (OTM puts)
      ce_strikes = [
        atm_strike,
        atm_strike + strike_interval,
        atm_strike + (2 * strike_interval)
      ].select { |s| available_strikes.include?(s) }

      pe_strikes = [
        atm_strike,
        atm_strike - strike_interval,
        atm_strike - (2 * strike_interval)
      ].select { |s| available_strikes.include?(s) }

      ServiceTestHelper.print_info("Spot Price: ₹#{spot_price.round(2)}, ATM Strike: #{atm_strike}")
      ServiceTestHelper.print_info("CE Strikes (OTM): #{ce_strikes.map { |s| offset = (s - atm_strike) / strike_interval; offset == 0 ? "#{s} (ATM)" : "#{s} (ATM+#{offset.to_i})" }.join(', ')}")
      ServiceTestHelper.print_info("PE Strikes (OTM): #{pe_strikes.map { |s| offset = (s - atm_strike) / strike_interval; offset == 0 ? "#{s} (ATM)" : "#{s} (ATM#{offset.to_i})" }.join(', ')}")

      # Filter derivatives to only ATM/2OTM strikes with correct option types
      # Exclude test derivatives (security_id starts with "TEST_")
      # Only include current/upcoming expiries
      today = Date.today
      derivatives = Derivative.where(underlying_symbol: 'NIFTY')
                               .where(
                                 '(strike_price IN (?) AND option_type = ?) OR (strike_price IN (?) AND option_type = ?)',
                                 ce_strikes, 'CE',
                                 pe_strikes, 'PE'
                               )
                               .where.not("security_id LIKE 'TEST_%'")
                               .where('expiry_date >= ?', today)
                               .order(:strike_price, :option_type, :expiry_date)
                               .limit(20)

      ServiceTestHelper.print_info("NIFTY derivatives (ATM/2OTM, real only, current expiry): #{derivatives.count}")

      if derivatives.any?
        # Group by strike and option_type to show unique combinations
        # For each group, show all derivatives with their expiry dates
        grouped = derivatives.group_by { |d| [d.strike_price, d.option_type] }

        grouped.each do |(strike, opt_type), group|
          offset = (strike - atm_strike) / strike_interval
          strike_label = if offset == 0
                           'ATM'
                         elsif offset > 0
                           "ATM+#{offset.to_i}"
                         else
                           "ATM#{offset.to_i}"
                         end

          # Show all derivatives for this strike/type with expiry dates
          if group.size > 1
            # Multiple derivatives - show each with expiry
            ServiceTestHelper.print_info("  #{strike_label}: #{strike} #{opt_type} (#{group.size} derivatives with different expiries):")
            group.each do |derivative|
              ServiceTestHelper.print_info("    - Security ID: #{derivative.security_id}, Expiry: #{derivative.expiry_date.strftime('%Y-%m-%d')}")
            end
          else
            # Single derivative
            representative = group.first
            ServiceTestHelper.print_info("  #{strike_label}: #{strike} #{opt_type} - Security ID: #{representative.security_id}, Expiry: #{representative.expiry_date.strftime('%Y-%m-%d')}")
          end
        end
      else
        ServiceTestHelper.print_warning('No ATM/2OTM derivatives found in database')
        ServiceTestHelper.print_info('Available strikes in option chain: ' + available_strikes.first(10).join(', ') + '...')
      end
    else
      ServiceTestHelper.print_warning('No option chain data available - showing all derivatives (excluding test)')
      derivatives = Derivative.where(underlying_symbol: 'NIFTY')
                               .where.not("security_id LIKE 'TEST_%'")
                               .where('expiry_date >= ?', Date.today)
                               .limit(5)
      ServiceTestHelper.print_info("NIFTY derivatives: #{derivatives.count}")
      derivatives.each do |derivative|
        ServiceTestHelper.print_info("  #{derivative.strike_price} #{derivative.option_type} - Security ID: #{derivative.security_id}, Expiry: #{derivative.expiry_date}")
      end
    end
  rescue StandardError => e
    ServiceTestHelper.print_warning("Failed to fetch option chain: #{e.message}")
    derivatives = Derivative.where(underlying_symbol: 'NIFTY')
                             .where.not("security_id LIKE 'TEST_%'")
                             .where('expiry_date >= ?', Date.today)
                             .limit(5)
    ServiceTestHelper.print_info("NIFTY derivatives: #{derivatives.count}")
    derivatives.each do |derivative|
      ServiceTestHelper.print_info("  #{derivative.strike_price} #{derivative.option_type} - Security ID: #{derivative.security_id}, Expiry: #{derivative.expiry_date}")
    end
  end
else
  ServiceTestHelper.print_warning('NIFTY instrument not found')
  derivatives = Derivative.where(underlying_symbol: 'NIFTY')
                           .where.not("security_id LIKE 'TEST_%'")
                           .where('expiry_date >= ?', Date.today)
                           .limit(5)
  ServiceTestHelper.print_info("NIFTY derivatives: #{derivatives.count}")
end

# Test 6: Integration with TickCache (ATM/2OTM derivatives only)
ServiceTestHelper.print_section('6. Integration with TickCache (ATM/2OTM)')
if defined?(derivatives) && defined?(atm_strike) && defined?(strike_interval) && derivatives.any?
  # Filter out test derivatives - only use real ones
  real_derivatives = derivatives.reject { |d| d.security_id.to_s.start_with?('TEST_') }

  if real_derivatives.empty?
    ServiceTestHelper.print_warning('No real derivatives found (only test derivatives available)')
    ServiceTestHelper.print_info('Test derivatives cannot be used for LTP testing as they have synthetic security IDs')
  else
    # Test with ATM CE derivative first (preferred for bullish), then ATM PE, then others
    # Try multiple derivatives in order of preference to find one with LTP
    test_derivatives = [
      real_derivatives.find { |d| d.strike_price == atm_strike && d.option_type == 'CE' },
      real_derivatives.find { |d| d.strike_price == atm_strike && d.option_type == 'PE' },
      real_derivatives.find { |d| (d.strike_price - atm_strike).abs <= strike_interval && d.option_type == 'CE' },
      real_derivatives.find { |d| (d.strike_price - atm_strike).abs <= strike_interval && d.option_type == 'PE' }
    ].compact.uniq

    atm_derivative = test_derivatives.first

    if atm_derivative
      # Use the full LTP retrieval pattern (same as production services)
      # This matches RiskManagerService.get_paper_ltp() and PositionSyncService.get_paper_ltp()
      ltp = nil

      # 1. Try derivative.ltp() (includes WebSocket cache, Redis cache, and API fallback)
      begin
        ltp = atm_derivative.ltp&.to_f
      rescue StandardError => e
        ServiceTestHelper.print_warning("derivative.ltp() failed: #{e.message}")
      end

      # 2. If still no LTP, try TickCache directly
      unless ltp&.positive?
        seg = atm_derivative.exchange_segment || 'NSE_FNO'
        sid = atm_derivative.security_id
        ltp = Live::TickCache.ltp(seg, sid)
      end

      # 3. If still no LTP, try RedisTickCache
      unless ltp&.positive?
        seg = atm_derivative.exchange_segment || 'NSE_FNO'
        sid = atm_derivative.security_id
        tick_data = Live::RedisTickCache.instance.fetch_tick(seg, sid)
        ltp = tick_data&.dig(:ltp)&.to_f
      end

      # 4. If still no LTP, try fetch_ltp_from_api_for_segment
      unless ltp&.positive?
        begin
          seg = atm_derivative.exchange_segment || 'NSE_FNO'
          sid = atm_derivative.security_id.to_s
          ltp = atm_derivative.fetch_ltp_from_api_for_segment(segment: seg, security_id: sid)&.to_f
          if ltp&.positive?
            ServiceTestHelper.print_info("Fetched LTP from API for #{atm_derivative.strike_price} #{atm_derivative.option_type}")
          end
        rescue StandardError => e
          ServiceTestHelper.print_warning("API fetch failed: #{e.message}")
        end
      end

      # 5. Last resort: direct API call via ServiceTestHelper
      unless ltp&.positive?
        seg = atm_derivative.exchange_segment || 'NSE_FNO'
        sid = atm_derivative.security_id.to_s
        api_ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid, suppress_rate_limit_warning: true)
        if api_ltp
          ltp = api_ltp
          ServiceTestHelper.print_info("Fetched LTP from DhanHQ API (direct) for #{atm_derivative.strike_price} #{atm_derivative.option_type}")
        end
      end

      if ltp&.positive?
        offset = (atm_derivative.strike_price - atm_strike) / strike_interval
        strike_label = offset == 0 ? 'ATM' : (offset > 0 ? "ATM+#{offset.to_i}" : "ATM#{offset.to_i}")
        expiry_str = atm_derivative.expiry_date.strftime('%Y-%m-%d')
        ServiceTestHelper.print_success("#{strike_label} (#{atm_derivative.strike_price} #{atm_derivative.option_type}, Expiry: #{expiry_str}): LTP = ₹#{ltp.round(2)}")
      else
        # Try a few more derivatives if the first one fails
        tried_derivatives = [atm_derivative]
        found_ltp = false

        real_derivatives.first(5).each do |derivative|
          next if tried_derivatives.include?(derivative)

          begin
            test_ltp = derivative.ltp&.to_f
            if test_ltp&.positive?
              offset = (derivative.strike_price - atm_strike) / strike_interval
              strike_label = offset == 0 ? 'ATM' : (offset > 0 ? "ATM+#{offset.to_i}" : "ATM#{offset.to_i}")
              expiry_str = derivative.expiry_date.strftime('%Y-%m-%d')
              ServiceTestHelper.print_success("#{strike_label} (#{derivative.strike_price} #{derivative.option_type}, Expiry: #{expiry_str}): LTP = ₹#{test_ltp.round(2)}")
              found_ltp = true
              break
            end
          rescue StandardError => e
            # Continue to next derivative
          end
        end

        unless found_ltp
          ServiceTestHelper.print_info("#{atm_derivative.strike_price} #{atm_derivative.option_type}: No LTP available")
          ServiceTestHelper.print_info("  Tried: derivative.ltp(), TickCache, RedisTickCache, fetch_ltp_from_api_for_segment(), direct API")
          ServiceTestHelper.print_info("  This is normal if:")
          ServiceTestHelper.print_info("    - Market is closed")
          ServiceTestHelper.print_info("    - Derivative is not actively traded")
          ServiceTestHelper.print_info("    - WebSocket is not subscribed to this derivative")
        end
      end
    end
  end
end

ServiceTestHelper.print_success('Options services test completed')

