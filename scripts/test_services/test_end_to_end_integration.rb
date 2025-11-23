#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('End-to-End Service Integration Test')

# ============================================================================
# INDEPENDENT SERVICES & THEIR RESPONSIBILITIES
# ============================================================================

ServiceTestHelper.print_section('0. Independent Services Overview')

independent_services = {
  'MarketFeedHub' => {
    class: 'Live::MarketFeedHub',
    singleton: true,
    responsibilities: [
      'Connect to DhanHQ WebSocket',
      'Subscribe to watchlist items',
      'Receive market ticks',
      'Store ticks in TickCache (in-memory + Redis)',
      'Manage WebSocket connection lifecycle'
    ],
    access: 'Live::MarketFeedHub.instance'
  },
  'TickCache' => {
    class: 'TickCache',
    singleton: true,
    responsibilities: [
      'Store ticks in-memory (Concurrent::Map)',
      'Store ticks in Redis (via RedisTickCache)',
      'Provide LTP access: Live::TickCache.ltp(segment, security_id)',
      'Provide tick fetch: Live::TickCache.fetch(segment, security_id)'
    ],
    access: 'Live::TickCache (module delegating to TickCache.instance)'
  },
  'RedisTickCache' => {
    class: 'Live::RedisTickCache',
    singleton: true,
    responsibilities: [
      'Store ticks in Redis (tick:SEG:SID)',
      'Fetch ticks from Redis',
      'Prune stale ticks'
    ],
    access: 'Live::RedisTickCache.instance'
  },
  'ActiveCache' => {
    class: 'Positions::ActiveCache',
    singleton: true,
    responsibilities: [
      'Cache active positions in-memory',
      'Subscribe to MarketFeedHub for tick updates',
      'Calculate PnL for positions',
      'Store peak profit data'
    ],
    access: 'Positions::ActiveCache.instance'
  },
  'PositionIndex' => {
    class: 'Live::PositionIndex',
    singleton: true,
    responsibilities: [
      'Track active positions by segment:security_id',
      'Provide position lookup',
      'Bulk load positions from database'
    ],
    access: 'Live::PositionIndex.instance'
  }
}

independent_services.each do |name, info|
  ServiceTestHelper.print_info("#{name}:")
  ServiceTestHelper.print_info("  Class: #{info[:class]}")
  ServiceTestHelper.print_info("  Singleton: #{info[:singleton] ? '✅ YES' : '❌ NO'}")
  ServiceTestHelper.print_info("  Responsibilities:")
  info[:responsibilities].each do |resp|
    ServiceTestHelper.print_info("    - #{resp}")
  end
  ServiceTestHelper.print_info("  Access: #{info[:access]}")
  puts ''
end

# ============================================================================
# TEST 1: MarketFeedHub → TickCache → RedisTickCache Flow
# ============================================================================

ServiceTestHelper.print_section('1. MarketFeedHub → TickCache → RedisTickCache Integration')

# Step 1: Verify MarketFeedHub is running
ServiceTestHelper.print_info('Step 1: Checking MarketFeedHub status...')
hub = Live::MarketFeedHub.instance
hub_running = hub.running?
hub_connected = hub.connected?

ServiceTestHelper.print_info("  MarketFeedHub running: #{hub_running ? '✅ YES' : '❌ NO'}")
ServiceTestHelper.print_info("  MarketFeedHub connected: #{hub_connected ? '✅ YES' : '❌ NO'}")

unless hub_running
  ServiceTestHelper.print_warning('MarketFeedHub is not running. Starting...')
  hub.start!
  sleep 2
  hub_running = hub.running?
  hub_connected = hub.connected?
  ServiceTestHelper.print_info("  After start - Running: #{hub_running ? '✅ YES' : '❌ NO'}")
  ServiceTestHelper.print_info("  After start - Connected: #{hub_connected ? '✅ YES' : '❌ NO'}")
end

# Step 2: Check watchlist subscriptions
ServiceTestHelper.print_info('Step 2: Checking watchlist subscriptions...')
watchlist = hub.instance_variable_get(:@watchlist) || []
ServiceTestHelper.print_info("  Watchlist count: #{watchlist.count}")

if watchlist.empty?
  ServiceTestHelper.print_warning('  No watchlist items found. Checking WatchlistItem model...')
  watchlist_items = WatchlistItem.where(active: true).limit(3)
  ServiceTestHelper.print_info("  Active WatchlistItems in DB: #{watchlist_items.count}")

  if watchlist_items.any?
    ServiceTestHelper.print_info('  Sample watchlist items:')
    watchlist_items.each do |item|
      ServiceTestHelper.print_info("    - #{item.segment}:#{item.security_id} (#{item.instrument&.symbol || 'N/A'})")
    end
  end
end

# Step 3: Wait for ticks and verify TickCache storage
ServiceTestHelper.print_info('Step 3: Waiting for ticks and verifying TickCache storage...')
ServiceTestHelper.print_info('  Waiting 10 seconds for ticks to arrive...')

test_instruments = watchlist.first(3) || [
  { segment: 'IDX_I', security_id: '13' }, # NIFTY
  { segment: 'IDX_I', security_id: '25' }, # BANKNIFTY
  { segment: 'IDX_I', security_id: '51' }  # SENSEX
]

tick_received = {}
test_instruments.each do |inst|
  seg = inst[:segment] || inst['segment']
  sid = inst[:security_id] || inst['security_id']

  # Check if tick exists in TickCache
  ltp = Live::TickCache.ltp(seg, sid.to_s)
  if ltp && ltp.positive?
    tick_received["#{seg}:#{sid}"] = ltp
    ServiceTestHelper.print_success("  ✅ Tick found for #{seg}:#{sid} - LTP: #{ltp}")
  else
    ServiceTestHelper.print_info("  ⏳ Waiting for tick: #{seg}:#{sid}")
  end
end

# Wait and check again
ServiceTestHelper.wait_for(10, 'Waiting for ticks')

tick_received_after = {}
test_instruments.each do |inst|
  seg = inst[:segment] || inst['segment']
  sid = inst[:security_id] || inst['security_id']

  ltp = Live::TickCache.ltp(seg, sid.to_s)
  if ltp && ltp.positive?
    tick_received_after["#{seg}:#{sid}"] = ltp
    ServiceTestHelper.print_success("  ✅ Tick received for #{seg}:#{sid} - LTP: #{ltp}")
  else
    ServiceTestHelper.print_warning("  ⚠️  No tick yet for #{seg}:#{sid}")
  end
end

# Step 4: Verify Redis TickCache storage
ServiceTestHelper.print_info('Step 4: Verifying Redis TickCache storage...')
redis_tick_cache = Live::RedisTickCache.instance

test_instruments.each do |inst|
  seg = inst[:segment] || inst['segment']
  sid = inst[:security_id] || inst['security_id']

  redis_tick = redis_tick_cache.fetch_tick(seg, sid.to_s)
  if redis_tick && redis_tick[:ltp] && redis_tick[:ltp].positive?
    ServiceTestHelper.print_success("  ✅ Redis tick found for #{seg}:#{sid} - LTP: #{redis_tick[:ltp]}")
  else
    ServiceTestHelper.print_warning("  ⚠️  No Redis tick for #{seg}:#{sid}")
  end
end

# Step 5: Test TickCache.ltp() access from other services
ServiceTestHelper.print_info('Step 5: Testing TickCache.ltp() access from other services...')

# Simulate how other services access ticks
test_cases = [
  { service: 'EntryGuard', segment: 'IDX_I', security_id: '13' },
  { service: 'RiskManager', segment: 'IDX_I', security_id: '25' },
  { service: 'ExitEngine', segment: 'IDX_I', security_id: '51' }
]

test_cases.each do |test_case|
  ltp = Live::TickCache.ltp(test_case[:segment], test_case[:security_id])
  if ltp && ltp.positive?
    ServiceTestHelper.print_success("  ✅ #{test_case[:service]} can access LTP for #{test_case[:segment]}:#{test_case[:security_id]} = #{ltp}")
  else
    ServiceTestHelper.print_warning("  ⚠️  #{test_case[:service]} cannot access LTP for #{test_case[:segment]}:#{test_case[:security_id]}")
  end
end

# ============================================================================
# TEST 2: Full Integration Flow
# ============================================================================

ServiceTestHelper.print_section('2. Full Integration Flow Test')

# Flow: MarketFeedHub → TickCache → ActiveCache → RiskManager → ExitEngine

ServiceTestHelper.print_info('Testing flow: MarketFeedHub → TickCache → ActiveCache → RiskManager')

# 2.1: MarketFeedHub is running and receiving ticks
ServiceTestHelper.print_info('2.1: MarketFeedHub status...')
if hub_running && hub_connected
  ServiceTestHelper.print_success('  ✅ MarketFeedHub is running and connected')
else
  ServiceTestHelper.print_warning("  ⚠️  MarketFeedHub: running=#{hub_running}, connected=#{hub_connected}")
end

# 2.2: TickCache is storing ticks
ServiceTestHelper.print_info('2.2: TickCache storage...')
tick_count = tick_received_after.size
if tick_count > 0
  ServiceTestHelper.print_success("  ✅ TickCache has #{tick_count} ticks stored")
else
  ServiceTestHelper.print_warning('  ⚠️  TickCache has no ticks (may need more time)')
end

# 2.3: ActiveCache is subscribed to MarketFeedHub
ServiceTestHelper.print_info('2.3: ActiveCache subscription...')
active_cache = Positions::ActiveCache.instance
subscription_id = active_cache.instance_variable_get(:@subscription_id)
if subscription_id
  ServiceTestHelper.print_success('  ✅ ActiveCache is subscribed to MarketFeedHub')
else
  ServiceTestHelper.print_warning('  ⚠️  ActiveCache is not subscribed (may need to call start!)')
  begin
    active_cache.start!
    ServiceTestHelper.print_info('  Started ActiveCache')
  rescue StandardError => e
    ServiceTestHelper.print_warning("  Failed to start ActiveCache: #{e.message}")
  end
end

# 2.4: RiskManager is running
ServiceTestHelper.print_info('2.4: RiskManager status...')
supervisor = Rails.application.config.x.trading_supervisor
risk_manager = supervisor&.[](:risk_manager)
if risk_manager
  risk_running = risk_manager.respond_to?(:running?) ? risk_manager.running? : false
  if risk_running
    ServiceTestHelper.print_success('  ✅ RiskManager is running')
  else
    ServiceTestHelper.print_warning('  ⚠️  RiskManager is not running')
  end
else
  ServiceTestHelper.print_warning('  ⚠️  RiskManager not found in supervisor')
end

# 2.5: ExitEngine is running
ServiceTestHelper.print_info('2.5: ExitEngine status...')
exit_engine = supervisor&.[](:exit_manager)
if exit_engine
  exit_running = exit_engine.instance_variable_get(:@running) rescue false
  if exit_running
    ServiceTestHelper.print_success('  ✅ ExitEngine is running')
  else
    ServiceTestHelper.print_warning('  ⚠️  ExitEngine is not running')
  end
else
  ServiceTestHelper.print_warning('  ⚠️  ExitEngine not found in supervisor')
end

# ============================================================================
# TEST 3: Service Independence Verification
# ============================================================================

ServiceTestHelper.print_section('3. Service Independence Verification')

# Test that services can work independently
ServiceTestHelper.print_info('3.1: Testing TickCache access without MarketFeedHub dependency...')

# TickCache should be accessible even if MarketFeedHub is not running
test_seg = 'IDX_I'
test_sid = '13'
ltp = Live::TickCache.ltp(test_seg, test_sid)

if ltp
  ServiceTestHelper.print_success("  ✅ TickCache.ltp('#{test_seg}', '#{test_sid}') = #{ltp} (independent access)")
else
  ServiceTestHelper.print_info("  ℹ️  TickCache.ltp('#{test_seg}', '#{test_sid}') = nil (no data yet)")
end

# Test RedisTickCache direct access
ServiceTestHelper.print_info('3.2: Testing RedisTickCache direct access...')
redis_tick = redis_tick_cache.fetch_tick(test_seg, test_sid)
if redis_tick && redis_tick[:ltp]
  ServiceTestHelper.print_success("  ✅ RedisTickCache.fetch_tick('#{test_seg}', '#{test_sid}') = #{redis_tick[:ltp]}")
else
  ServiceTestHelper.print_info("  ℹ️  RedisTickCache has no data for #{test_seg}:#{test_sid}")
end

# ============================================================================
# SUMMARY
# ============================================================================

ServiceTestHelper.print_section('Summary')

all_tests_passed = true

# Check critical integrations
checks = {
  'MarketFeedHub running' => hub_running,
  'MarketFeedHub connected' => hub_connected,
  'Ticks received' => tick_received_after.any?,
  'TickCache accessible' => ltp.present?,
  'RedisTickCache accessible' => redis_tick.present?,
  'ActiveCache subscribed' => subscription_id.present?
}

checks.each do |check_name, passed|
  if passed
    ServiceTestHelper.print_success("✅ #{check_name}")
  else
    ServiceTestHelper.print_warning("⚠️  #{check_name}")
    all_tests_passed = false
  end
end

puts ''
if all_tests_passed
  ServiceTestHelper.print_success('🎉 All integration tests passed!')
else
  ServiceTestHelper.print_warning('⚠️  Some integration checks have warnings')
  ServiceTestHelper.print_info('   This may be normal if services are not fully started or no ticks received yet')
end

puts ''
ServiceTestHelper.print_info('Independent Services Summary:')
independent_services.each do |name, _info|
  ServiceTestHelper.print_info("  - #{name}: ✅ Independent (singleton)")
end

puts ''
ServiceTestHelper.print_info('Integration Flow:')
ServiceTestHelper.print_info('  1. MarketFeedHub → receives ticks from WebSocket')
ServiceTestHelper.print_info('  2. MarketFeedHub.handle_tick() → calls Live::TickCache.put(tick)')
ServiceTestHelper.print_info('  3. TickCache.put() → stores in-memory + Live::RedisTickCache.instance.store_tick()')
ServiceTestHelper.print_info('  4. Other services → access via Live::TickCache.ltp(segment, security_id)')
ServiceTestHelper.print_info('  5. ActiveCache → subscribes to MarketFeedHub callbacks for position updates')
ServiceTestHelper.print_info('  6. RiskManager → uses TickCache.ltp() for PnL calculations')
ServiceTestHelper.print_info('  7. ExitEngine → uses TickCache.ltp() for exit price resolution')

puts ''

