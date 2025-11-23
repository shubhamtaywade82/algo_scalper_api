#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('RedisTickCache Service Test')

redis_cache = Live::RedisTickCache.instance

# Track test keys for cleanup
test_keys_created = []

# Test 1: Store test ticks (simulating MarketFeedHub handle_tick flow)
ServiceTestHelper.print_section('1. Storing Test Ticks (Ticker + Prev Close)')
test_segment = 'IDX_I'
test_security_id = '13' # NIFTY

# Try to fetch real LTP from DhanHQ API
real_ltp = ServiceTestHelper.fetch_ltp(segment: test_segment, security_id: test_security_id)
if real_ltp
  ServiceTestHelper.print_info("Fetched real LTP from DhanHQ API: ₹#{real_ltp}")
else
  ServiceTestHelper.print_info('Using test data instead')
end

# Use real LTP if available, otherwise use test data
test_ltp = real_ltp || 26_068.15
test_prev_close = test_ltp + 124.0 # Simulate prev_close slightly higher

# Simulate MarketFeedHub.handle_tick() flow:
# 1. First tick: :ticker type with LTP
ticker_tick = {
  kind: :ticker,
  segment: test_segment,
  security_id: test_security_id,
  ltp: test_ltp,
  ts: Time.current.to_i
}

ServiceTestHelper.print_info("Simulating ticker tick: #{ticker_tick.inspect}")

# Store via TickCache.put() (same as MarketFeedHub does)
result1 = Live::TickCache.put(ticker_tick)
test_keys_created << { segment: test_segment, security_id: test_security_id }

ServiceTestHelper.check_condition(
  result1.present?,
  'Ticker tick stored successfully via TickCache',
  'Failed to store ticker tick'
)

# 2. Second tick: :prev_close type
prev_close_tick = {
  kind: :prev_close,
  segment: test_segment,
  security_id: test_security_id,
  prev_close: test_prev_close,
  oi_prev: 0
}

ServiceTestHelper.print_info("Simulating prev_close tick: #{prev_close_tick.inspect}")

# Store via TickCache.put() (prev_close should merge with existing ticker data)
result2 = Live::TickCache.put(prev_close_tick)

ServiceTestHelper.check_condition(
  result2.present?,
  'Prev close tick stored successfully via TickCache',
  'Failed to store prev_close tick'
)

# Test 2: Verify data is actually in Redis (direct verification)
ServiceTestHelper.print_section('2. Direct Redis Verification')
begin
  require 'redis'
  redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
  redis_key = "tick:#{test_segment}:#{test_security_id}"
  raw_redis_data = redis.hgetall(redis_key)

  if raw_redis_data.any?
    ServiceTestHelper.print_success("Redis key exists: #{redis_key}")
    ServiceTestHelper.print_info("Raw Redis data: #{raw_redis_data.inspect}")

    redis_has_ltp = raw_redis_data['ltp'].present?
    redis_has_prev_close = raw_redis_data['prev_close'].present?

    ServiceTestHelper.check_condition(
      redis_has_ltp && redis_has_prev_close,
      'Both LTP and prev_close in Redis',
      'Missing data in Redis'
    )
  else
    ServiceTestHelper.print_warning("Redis key not found: #{redis_key}")
    ServiceTestHelper.print_info('Data may not have been persisted to Redis')
  end
rescue StandardError => e
  ServiceTestHelper.print_warning("Could not verify Redis directly: #{e.message}")
end

# Test 2b: Fetch the stored tick via RedisTickCache (should have both ticker and prev_close data)
ServiceTestHelper.print_section('2b. Fetching Stored Tick via RedisTickCache (Merged Data)')
fetched = redis_cache.fetch_tick(test_segment, test_security_id)

if fetched.present?
  has_ltp = fetched[:ltp].present?
  has_prev_close = fetched[:prev_close].present?

  if has_ltp
    ServiceTestHelper.print_success("Fetched tick: LTP = ₹#{fetched[:ltp]}")
  else
    ServiceTestHelper.print_warning('LTP missing in fetched tick')
  end

  if has_prev_close
    ServiceTestHelper.print_success("Prev Close = ₹#{fetched[:prev_close]}")
  else
    ServiceTestHelper.print_warning('Prev Close missing in fetched tick')
  end

  ServiceTestHelper.print_info("Tick data:\n#{ServiceTestHelper.format_hash(fetched)}")

  ServiceTestHelper.check_condition(
    has_ltp && has_prev_close,
    'Both ticker and prev_close data present',
    'Missing ticker or prev_close data'
  )
else
  ServiceTestHelper.print_error('Failed to fetch tick from RedisTickCache')
end

# Test 3: Test LTP retrieval via TickCache
ServiceTestHelper.print_section('3. LTP Retrieval via TickCache')
tick_cache_ltp = Live::TickCache.ltp(test_segment, test_security_id)
ServiceTestHelper.check_condition(
  tick_cache_ltp && (tick_cache_ltp - test_ltp).abs < 0.01,
  "TickCache.ltp() retrieved correctly: ₹#{tick_cache_ltp}",
  "LTP mismatch: expected ₹#{test_ltp}, got #{tick_cache_ltp.inspect}"
)

# Test 3b: Test prev_close retrieval
ServiceTestHelper.print_section('3b. Prev Close Retrieval')
fetched_tick = redis_cache.fetch_tick(test_segment, test_security_id)
prev_close = fetched_tick[:prev_close] if fetched_tick
ServiceTestHelper.check_condition(
  prev_close && (prev_close - test_prev_close).abs < 0.01,
  "Prev Close retrieved correctly: ₹#{prev_close}",
  "Prev Close mismatch: expected ₹#{test_prev_close}, got #{prev_close.inspect}"
)

# Test 4: Test with multiple segments (simulating real MarketFeedHub ticks)
ServiceTestHelper.print_section('4. Multiple Segments Test (Ticker + Prev Close)')
test_data = [
  { segment: 'IDX_I', security_id: '13', name: 'NIFTY', fallback_ltp: 26_068.15, fallback_prev_close: 26_192.15 },
  { segment: 'IDX_I', security_id: '25', name: 'BANKNIFTY', fallback_ltp: 58_867.70, fallback_prev_close: 59_347.70 },
  { segment: 'IDX_I', security_id: '51', name: 'SENSEX', fallback_ltp: 85_231.92, fallback_prev_close: 85_632.68 }
]

test_data.each_with_index do |data, index|
  # Add small delay between API calls to avoid rate limiting
  sleep(0.5) if index.positive?

  # Try to fetch real LTP from API (suppress rate limit warnings)
  real_ltp = ServiceTestHelper.fetch_ltp(
    segment: data[:segment],
    security_id: data[:security_id],
    suppress_rate_limit_warning: true
  )
  ServiceTestHelper.print_info("#{data[:name]}: Using fallback data") unless real_ltp

  ltp_to_use = real_ltp || data[:fallback_ltp]
  prev_close_to_use = real_ltp ? (real_ltp + 124.0) : data[:fallback_prev_close]
  source = real_ltp ? 'API' : 'test data'

  # Simulate MarketFeedHub.handle_tick() - store ticker first
  ticker_tick = {
    kind: :ticker,
    segment: data[:segment],
    security_id: data[:security_id],
    ltp: ltp_to_use,
    ts: Time.current.to_i
  }
  Live::TickCache.put(ticker_tick)
  test_keys_created << { segment: data[:segment], security_id: data[:security_id] }

  # Then store prev_close (should merge with ticker data)
  prev_close_tick = {
    kind: :prev_close,
    segment: data[:segment],
    security_id: data[:security_id],
    prev_close: prev_close_to_use,
    oi_prev: 0
  }
  Live::TickCache.put(prev_close_tick)

  # Verify both are stored
  fetched_tick = redis_cache.fetch_tick(data[:segment], data[:security_id])
  fetched_ltp = fetched_tick[:ltp] if fetched_tick
  fetched_prev_close = fetched_tick[:prev_close] if fetched_tick

  ltp_ok = fetched_ltp && (fetched_ltp - ltp_to_use).abs < 0.01
  prev_close_ok = fetched_prev_close && (fetched_prev_close - prev_close_to_use).abs < 0.01

  ServiceTestHelper.check_condition(
    ltp_ok && prev_close_ok,
    "#{data[:segment]}:#{data[:security_id]} = LTP: ₹#{fetched_ltp}, Prev: ₹#{fetched_prev_close} (#{source})",
    "#{data[:segment]}:#{data[:security_id]} failed - LTP: #{ltp_ok ? '✅' : '❌'}, Prev: #{prev_close_ok ? '✅' : '❌'}"
  )
end

# Test 5: Integration with TickCache (Redis fallback)
ServiceTestHelper.print_section('5. Integration with TickCache (Redis Fallback)')
# Store in Redis directly, then check if TickCache can retrieve (fallback mechanism)
test_security_id_fallback = '999'
test_keys_created << { segment: test_segment, security_id: test_security_id_fallback }
redis_cache.store_tick(
  segment: test_segment,
  security_id: test_security_id_fallback,
  data: {
    ltp: 10_000.0,
    prev_close: 10_100.0,
    timestamp: Time.current
  }
)

# TickCache should fallback to Redis
tick_cache_ltp = Live::TickCache.ltp(test_segment, test_security_id_fallback)
tick_cache_full = Live::TickCache.fetch(test_segment, test_security_id_fallback)

ltp_ok = tick_cache_ltp && (tick_cache_ltp - 10_000.0).abs < 0.01
prev_close_ok = tick_cache_full && tick_cache_full[:prev_close] && (tick_cache_full[:prev_close] - 10_100.0).abs < 0.01

ServiceTestHelper.check_condition(
  ltp_ok && prev_close_ok,
  "TickCache retrieved from Redis: LTP=₹#{tick_cache_ltp}, Prev=₹#{tick_cache_full[:prev_close]}",
  "TickCache failed to retrieve from Redis - LTP: #{ltp_ok ? '✅' : '❌'}, Prev: #{prev_close_ok ? '✅' : '❌'}"
)

# Test 6: Verify MarketFeedHub → TickCache → RedisTickCache flow
ServiceTestHelper.print_section('6. MarketFeedHub → TickCache → RedisTickCache Flow')
# Simulate actual MarketFeedHub.handle_tick() behavior
test_security_id_flow = '888'
flow_ticker = {
  kind: :ticker,
  segment: test_segment,
  security_id: test_security_id_flow,
  ltp: 15_000.0,
  ts: Time.current.to_i
}

ServiceTestHelper.print_info('Simulating MarketFeedHub.handle_tick() with ticker...')
# MarketFeedHub calls: Live::TickCache.put(tick) if tick[:ltp].to_f.positive? || tick[:prev_close].to_f.positive?
Live::TickCache.put(flow_ticker) if flow_ticker[:ltp].to_f.positive?
test_keys_created << { segment: test_segment, security_id: test_security_id_flow }

# Wait a moment for Redis write
sleep 0.1

# Verify it's in RedisTickCache
flow_tick_redis = redis_cache.fetch_tick(test_segment, test_security_id_flow)
flow_ltp_redis = flow_tick_redis[:ltp] if flow_tick_redis

# Also verify Redis directly
begin
  require 'redis'
  redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
  flow_redis_key = "tick:#{test_segment}:#{test_security_id_flow}"
  flow_redis_raw = redis.hgetall(flow_redis_key)
  flow_redis_has_data = flow_redis_raw.any?
  flow_redis_ltp = flow_redis_raw['ltp']&.to_f

  ServiceTestHelper.print_info("Direct Redis check: key=#{flow_redis_key}, has_data=#{flow_redis_has_data}, ltp=#{flow_redis_ltp}")
rescue StandardError => e
  ServiceTestHelper.print_warning("Could not verify Redis directly: #{e.message}")
  flow_redis_has_data = false
end

ServiceTestHelper.check_condition(
  flow_ltp_redis && (flow_ltp_redis - 15_000.0).abs < 0.01 && flow_redis_has_data,
  "MarketFeedHub → TickCache → RedisTickCache flow works: LTP=₹#{flow_ltp_redis} (verified in Redis)",
  "Flow failed: expected ₹15000.0, got #{flow_ltp_redis.inspect}, Redis verified: #{flow_redis_has_data ? '✅' : '❌'}"
)

# Test 7: Verify persistence (clear memory, fetch from Redis)
ServiceTestHelper.print_section('7. Persistence Verification (Memory vs Redis)')
# Clear in-memory cache to force Redis fallback
test_security_id_persist = '777'
persist_ticker = {
  kind: :ticker,
  segment: test_segment,
  security_id: test_security_id_persist,
  ltp: 30_000.0,
  ts: Time.current.to_i
}

# Store via TickCache (stores in memory + Redis)
Live::TickCache.put(persist_ticker)
test_keys_created << { segment: test_segment, security_id: test_security_id_persist }

# Clear in-memory cache
TickCache.instance.instance_variable_set(:@map, Concurrent::Map.new)

# Now fetch - should come from Redis
persist_ltp = Live::TickCache.ltp(test_segment, test_security_id_persist)
persist_full = Live::TickCache.fetch(test_segment, test_security_id_persist)

persist_ok = persist_ltp && (persist_ltp - 30_000.0).abs < 0.01

ServiceTestHelper.check_condition(
  persist_ok,
  "Persistence verified: LTP=₹#{persist_ltp} (retrieved from Redis after memory clear)",
  "Persistence failed: expected ₹30000.0, got #{persist_ltp.inspect}"
)

# Test 8: Fetch all ticks
ServiceTestHelper.print_section('8. Fetch All Ticks')
all_ticks = redis_cache.fetch_all
ServiceTestHelper.print_info("Total ticks in Redis: #{all_ticks.size}")
if all_ticks.any?
  sample_keys = all_ticks.keys.first(3)
  ServiceTestHelper.print_info("Sample keys: #{sample_keys.join(', ')}")

  # Show sample tick data
  sample_key = sample_keys.first
  sample_tick = all_ticks[sample_key]
  if sample_tick
    ServiceTestHelper.print_info("Sample tick (#{sample_key}):")
    ServiceTestHelper.print_info("  LTP: #{sample_tick[:ltp] || 'N/A'}")
    ServiceTestHelper.print_info("  Prev Close: #{sample_tick[:prev_close] || 'N/A'}")
    ServiceTestHelper.print_info("  Timestamp: #{sample_tick[:timestamp] || sample_tick[:ts] || 'N/A'}")
    ServiceTestHelper.print_info("  Kind: #{sample_tick[:kind] || 'N/A'}")
  end
end

# Test 9: Cleanup test data
ServiceTestHelper.print_section('9. Cleanup Test Data')
# Remove duplicates from test_keys_created
unique_test_keys = test_keys_created.uniq

cleaned_count = 0
failed_count = 0

unique_test_keys.each do |key_data|
  success = redis_cache.clear_tick(key_data[:segment], key_data[:security_id])
  if success
    cleaned_count += 1
  else
    failed_count += 1
    ServiceTestHelper.print_warning("Failed to clean #{key_data[:segment]}:#{key_data[:security_id]}")
  end
rescue StandardError => e
  failed_count += 1
  ServiceTestHelper.print_warning("Error cleaning #{key_data[:segment]}:#{key_data[:security_id]}: #{e.message}")
end

ServiceTestHelper.print_success("Cleaned up #{cleaned_count} test key(s) from Redis") if cleaned_count.positive?

ServiceTestHelper.print_warning("#{failed_count} test key(s) could not be cleaned") if failed_count.positive?

ServiceTestHelper.print_success('RedisTickCache test completed')
