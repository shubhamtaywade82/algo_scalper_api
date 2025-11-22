#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('RedisTickCache Service Test')

redis_cache = Live::RedisTickCache.instance
tick_cache = TickCache.instance

# Test 1: Store a test tick (try real API first, fallback to test data)
ServiceTestHelper.print_section('1. Storing Test Tick')
test_segment = 'IDX_I'
test_security_id = '13' # NIFTY

# Try to fetch real LTP from DhanHQ API
real_ltp = ServiceTestHelper.fetch_ltp(segment: test_segment, security_id: test_security_id)
if real_ltp
  ServiceTestHelper.print_info("Fetched real LTP from DhanHQ API: ₹#{real_ltp}")
else
  ServiceTestHelper.print_info("Using test data instead")
end

# Use real LTP if available, otherwise use test data
test_ltp = real_ltp || 25_000.50
test_bid = real_ltp ? (test_ltp - 0.5) : (test_ltp - 0.5)
test_ask = real_ltp ? (test_ltp + 0.5) : (test_ltp + 0.5)

result = redis_cache.store_tick(
  segment: test_segment,
  security_id: test_security_id,
  data: {
    ltp: test_ltp,
    bid: test_bid,
    ask: test_ask,
    volume: 1000,
    timestamp: Time.current
  }
)

ServiceTestHelper.check_condition(
  result.present?,
  'Test tick stored successfully',
  'Failed to store test tick'
)

# Test 2: Fetch the stored tick
ServiceTestHelper.print_section('2. Fetching Stored Tick')
fetched = redis_cache.fetch_tick(test_segment, test_security_id)

if fetched.present? && fetched[:ltp]
  ServiceTestHelper.print_success("Fetched tick: LTP = ₹#{fetched[:ltp]}")
  ServiceTestHelper.print_info("Tick data:\n#{ServiceTestHelper.format_hash(fetched)}")
else
  ServiceTestHelper.print_error('Failed to fetch tick or LTP missing')
end

# Test 3: Test LTP retrieval
ServiceTestHelper.print_section('3. LTP Retrieval')
fetched_tick = redis_cache.fetch_tick(test_segment, test_security_id)
ltp = fetched_tick[:ltp] if fetched_tick
ServiceTestHelper.check_condition(
  ltp == test_ltp,
  "LTP retrieved correctly: ₹#{ltp}",
  "LTP mismatch: expected ₹#{test_ltp}, got #{ltp.inspect}"
)

# Test 4: Test with multiple segments (try real API first)
ServiceTestHelper.print_section('4. Multiple Segments Test')
test_data = [
  { segment: 'IDX_I', security_id: '13', name: 'NIFTY', fallback_ltp: 25_000.50 },
  { segment: 'IDX_I', security_id: '25', name: 'BANKNIFTY', fallback_ltp: 52_000.75 },
  { segment: 'IDX_I', security_id: '51', name: 'SENSEX', fallback_ltp: 75_000.25 }
]

test_data.each_with_index do |data, index|
  # Add small delay between API calls to avoid rate limiting
  sleep(0.5) if index > 0

  # Try to fetch real LTP from API (suppress rate limit warnings)
  real_ltp = ServiceTestHelper.fetch_ltp(
    segment: data[:segment],
    security_id: data[:security_id],
    suppress_rate_limit_warning: true
  )
  unless real_ltp
    ServiceTestHelper.print_info("#{data[:name]}: Using fallback data")
  end

  ltp_to_use = real_ltp || data[:fallback_ltp]
  source = real_ltp ? 'API' : 'test data'

  redis_cache.store_tick(
    segment: data[:segment],
    security_id: data[:security_id],
    data: { ltp: ltp_to_use, timestamp: Time.current }
  )
  fetched_tick = redis_cache.fetch_tick(data[:segment], data[:security_id])
  fetched_ltp = fetched_tick[:ltp] if fetched_tick
  ServiceTestHelper.check_condition(
    fetched_ltp == ltp_to_use,
    "#{data[:segment]}:#{data[:security_id]} = ₹#{fetched_ltp} (#{source})",
    "#{data[:segment]}:#{data[:security_id]} failed"
  )
end

# Test 5: Integration with TickCache
ServiceTestHelper.print_section('5. Integration with TickCache')
# Store in Redis, then check if TickCache can retrieve
redis_cache.store_tick(
  segment: test_segment,
  security_id: '999',
  data: { ltp: 10_000.0, timestamp: Time.current }
)

# TickCache should fallback to Redis
tick_cache_ltp = tick_cache.ltp(test_segment, '999')
ServiceTestHelper.check_condition(
  tick_cache_ltp == 10_000.0,
  "TickCache retrieved from Redis: ₹#{tick_cache_ltp}",
  'TickCache failed to retrieve from Redis'
)

# Test 6: Fetch all ticks
ServiceTestHelper.print_section('6. Fetch All Ticks')
all_ticks = redis_cache.fetch_all
ServiceTestHelper.print_info("Total ticks in Redis: #{all_ticks.size}")
if all_ticks.any?
  ServiceTestHelper.print_info("Sample keys: #{all_ticks.keys.first(3).join(', ')}")
end

ServiceTestHelper.print_success('RedisTickCache test completed')

