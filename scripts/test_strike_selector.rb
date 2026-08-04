# frozen_string_literal: true

# Script to test StrikeSelector in Rails console
# Usage: rails runner scripts/test_strike_selector.rb [INDEX_KEY]
# Or copy-paste into rails console

require_relative '../config/environment'

index_key = ARGV[0] || 'NIFTY'
puts "\n#{'=' * 80}"
puts "  Testing StrikeSelector for #{index_key}"
puts "#{'=' * 80}\n"

# 1. Check AlgoConfig
puts "\n--- 1. Checking AlgoConfig ---"
algo_cfg = AlgoConfig.fetch[:indices]&.find { |i| i[:key].to_s.upcase == index_key.to_s.upcase }
if algo_cfg.nil?
  puts "❌ AlgoConfig missing for #{index_key}"
  exit 1
end
puts "✅ AlgoConfig found: segment=#{algo_cfg[:segment]}, sid=#{algo_cfg[:sid]}"

# 2. Check spot price
puts "\n--- 2. Checking Spot Price ---"
spot_seg = algo_cfg[:segment]
spot_sid = algo_cfg[:sid]
spot_from_tick = Live::TickCache.ltp(spot_seg, spot_sid)
spot_from_redis = Live::RedisTickCache.instance.fetch_tick(spot_seg, spot_sid)&.dig(:ltp)&.to_f
spot_price = spot_from_tick || spot_from_redis

if spot_price&.positive?
  puts "✅ Spot price: ₹#{spot_price.round(2)} (from #{spot_from_tick ? 'TickCache' : 'RedisTickCache'})"
else
  puts "⚠️  No spot price in cache (TickCache=#{spot_from_tick}, Redis=#{spot_from_redis})"
  # Try API
  begin
    instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: spot_sid.to_s)
    if instrument
      spot_price = instrument.ltp&.to_f
      if spot_price&.positive?
        puts "✅ Spot price from API: ₹#{spot_price.round(2)}"
      else
        puts '❌ Could not fetch spot price from API'
        exit 1
      end
    else
      puts '❌ Index instrument not found in DB'
      exit 1
    end
  rescue StandardError => e
    puts "❌ Error fetching spot price: #{e.class} - #{e.message}"
    exit 1
  end
end

# 3. Check derivatives
puts "\n--- 3. Checking Derivatives ---"
instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: spot_sid.to_s)
if instrument.nil?
  puts '❌ Index instrument not found in DB'
  exit 1
end

expiry_list = instrument.expiry_list
if expiry_list.blank?
  puts "❌ No expiry list for #{index_key}"
  exit 1
end
puts "✅ Expiry list: #{expiry_list.first(3).join(', ')}"

nearest_expiry = expiry_list.first
expiry_obj = nearest_expiry.is_a?(Date) ? nearest_expiry : Date.parse(nearest_expiry.to_s)
derivatives_count = Derivative.where(
  underlying_symbol: index_key,
  expiry_date: expiry_obj
).where.not(option_type: [nil, '']).count

if derivatives_count.zero?
  puts "❌ No derivatives found for #{index_key} expiry #{nearest_expiry}"
  exit 1
end
puts "✅ Found #{derivatives_count} derivatives for nearest expiry (#{nearest_expiry})"

# Check CE derivatives specifically
ce_count = Derivative.where(
  underlying_symbol: index_key,
  expiry_date: expiry_obj,
  option_type: 'CE'
).count
puts "   - CE derivatives: #{ce_count}"

# 4. Test DerivativeChainAnalyzer
puts "\n--- 4. Testing DerivativeChainAnalyzer ---"
begin
  analyzer = Options::DerivativeChainAnalyzer.new(
    index_key: index_key,
    expiry: nil,
    config: {}
  )

  candidates = analyzer.select_candidates(limit: 5, direction: :bullish)
  if candidates.empty?
    puts '❌ DerivativeChainAnalyzer returned no candidates'
    puts "\n   Possible reasons:"
    puts '   - API chain fetch failed (fetch_option_chain returned nil)'
    puts '   - No LTP available for derivatives (not subscribed via WebSocket)'
    puts '   - All candidates filtered out by score_chain() filters'
    puts "\n   Checking chain data..."

    # Try to load chain manually
    chain = analyzer.send(:load_chain_for_expiry, expiry_obj.strftime('%Y-%m-%d'))
    puts "   Chain size: #{chain.size}"

    if chain.any?
      # Check how many have LTP
      with_ltp = chain.count { |o| o[:ltp]&.positive? }
      puts "   Candidates with LTP: #{with_ltp} / #{chain.size}"

      # Check CE candidates
      ce_candidates = chain.select { |o| o[:type] == 'CE' }
      ce_with_ltp = ce_candidates.count { |o| o[:ltp]&.positive? }
      puts "   CE candidates: #{ce_candidates.size} (with LTP: #{ce_with_ltp})"

      if ce_candidates.any?
        # Show sample with more details
        sample = ce_candidates.first(3)
        puts "\n   Sample CE candidates:"
        sample.each do |c|
          derivative = c[:derivative]
          segment = derivative&.exchange_segment || derivative&.segment || 'unknown'
          security_id = derivative&.security_id || 'unknown'
          puts "     - Strike: #{c[:strike]}, LTP: #{c[:ltp] || 'nil'}, OI: #{c[:oi] || 'nil'}, IV: #{c[:iv] || 'nil'}"
          puts "       Segment: #{segment}, Security ID: #{security_id}, Symbol: #{derivative&.symbol_name || 'N/A'}"

          # Try to fetch LTP manually
          next unless derivative && !c[:ltp]&.positive?

          begin
            seg = derivative.exchange_segment || 'NSE_FNO'
            sid = derivative.security_id.to_s
            puts "       Attempting manual LTP fetch: segment=#{seg}, security_id=#{sid}"
            manual_ltp = derivative.fetch_ltp_from_api_for_segment(segment: seg, security_id: sid)
            puts "       Manual LTP result: #{manual_ltp || 'nil'}"
          rescue StandardError => e
            puts "       Manual LTP fetch error: #{e.class} - #{e.message}"
          end
        end
      end
    else
      puts '   ❌ Chain is empty - API fetch likely failed'
    end
  else
    puts "✅ DerivativeChainAnalyzer found #{candidates.count} candidates"
    puts "\n   Top candidates:"
    candidates.first(3).each do |c|
      puts "     - Strike: #{c[:strike]}, Score: #{c[:score]&.round(2)}, LTP: ₹#{c[:ltp]&.round(2)}, OI: #{c[:oi]}, IV: #{c[:iv]&.round(2)}%"
    end
  end
rescue StandardError => e
  puts "❌ DerivativeChainAnalyzer error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# 5. Test StrikeSelector
puts "\n--- 5. Testing StrikeSelector ---"
begin
  strike_selector = Options::StrikeSelector.new
  inst_hash = strike_selector.select(
    index_key: index_key,
    direction: :bullish,
    expiry: nil,
    trend_score: nil
  )

  if inst_hash.nil?
    puts '❌ StrikeSelector returned nil'
    puts "\n   Common reasons:"
    puts '   - No spot price (checked above)'
    puts '   - No candidates from DerivativeChainAnalyzer (checked above)'
    puts "   - Candidates don't match allowed strike distance (ATM only with trend_score=nil)"
    puts '   - Candidates fail validation (liquidity/spread/premium)'
  else
    puts '✅ StrikeSelector found derivative!'
    puts "\n   Result:"
    puts "     - Symbol: #{inst_hash[:symbol] || 'N/A'}"
    puts "     - Security ID: #{inst_hash[:security_id]}"
    puts "     - Strike: #{inst_hash[:strike]}"
    puts "     - Option Type: #{inst_hash[:option_type]}"
    puts "     - LTP: ₹#{inst_hash[:ltp]&.round(2)}"
    puts "     - Exchange Segment: #{inst_hash[:exchange_segment]}"
    puts "     - Lot Size: #{inst_hash[:lot_size]}"

    # Try to find the derivative
    derivative = Derivative.find_by(
      segment: 'derivatives',
      security_id: inst_hash[:security_id]
    ) || Derivative.find_by(symbol_name: inst_hash[:symbol])

    if derivative
      puts "\n   ✅ Found derivative in DB:"
      puts "     - ID: #{derivative.id}"
      puts "     - Symbol: #{derivative.symbol_name}"
      puts "     - Strike: #{derivative.strike_price}"
      puts "     - Expiry: #{derivative.expiry_date}"
      puts "     - Lot Size: #{derivative.lot_size}"
    else
      puts "\n   ⚠️  Derivative not found in DB"
    end
  end
rescue StandardError => e
  puts "❌ StrikeSelector error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# 6. Check MarketFeedHub status (if running)
puts "\n--- 6. MarketFeedHub Status ---"
begin
  hub = Live::MarketFeedHub.instance
  if hub.running?
    puts '✅ MarketFeedHub is running'
    puts "   - Subscribed instruments: #{hub.instance_variable_get(:@watchlist)&.count || 0}"
  else
    puts '⚠️  MarketFeedHub is not running'
    puts '   - This means no real-time tick data is available'
    puts '   - StrikeSelector may fail without tick data or API data'
  end
rescue StandardError => e
  puts "⚠️  Could not check MarketFeedHub: #{e.message}"
end

puts "\n#{'=' * 80}"
puts '  Test Complete'
puts "#{'=' * 80}\n"
