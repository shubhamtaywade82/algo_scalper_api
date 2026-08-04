#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('MarketFeedHub Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items

hub = Live::MarketFeedHub.instance
tick_cache = TickCache.instance

# Test 1: Check if service is already running/connected
ServiceTestHelper.print_section('1. MarketFeedHub Status Check')
if hub.running?
  if hub.connected?
    ServiceTestHelper.print_success('MarketFeedHub is already running and connected')
    ServiceTestHelper.print_info("Connection state: #{hub.instance_variable_get(:@connection_state)}")
  else
    ServiceTestHelper.print_info('MarketFeedHub is running but not connected yet')
    ServiceTestHelper.print_info('Waiting for connection...')
    ServiceTestHelper.wait_for(3, 'Waiting for WebSocket connection')
  end
else
  # Not running, try to start
  ServiceTestHelper.print_info('MarketFeedHub is not running - starting...')
  if hub.start!
    ServiceTestHelper.print_success('MarketFeedHub started')
    ServiceTestHelper.wait_for(3, 'Waiting for WebSocket connection')
  else
    ServiceTestHelper.print_error('Failed to start MarketFeedHub')
    exit 1
  end
end

# Test 2: Verify WebSocket connection
ServiceTestHelper.print_section('2. WebSocket Connection Status')
if hub.running?
  if hub.connected?
    ServiceTestHelper.print_success("WebSocket connected: #{hub.connected?}")
  else
    ServiceTestHelper.print_warning('WebSocket not connected yet (may still be connecting)')
  end
  ServiceTestHelper.print_info("Connection state: #{hub.instance_variable_get(:@connection_state)}")
else
  ServiceTestHelper.print_error('MarketFeedHub is not running')
  exit 1
end

# Test 3: Subscribe to watchlist items
ServiceTestHelper.print_section('3. Subscribing to Watchlist Items')
# WatchlistItem uses polymorphic watchable, not direct instrument association
watchlist_items = WatchlistItem.where(active: true).includes(:watchable)
ServiceTestHelper.print_info("Found #{watchlist_items.count} active watchlist items")

if watchlist_items.any?
  pairs = watchlist_items.filter_map do |item|
    # Use watchable (polymorphic) - can be Instrument or Derivative
    watchable = item.watchable
    if watchable
      segment = watchable.respond_to?(:exchange_segment) ? watchable.exchange_segment : item.segment
      security_id = watchable.respond_to?(:security_id) ? watchable.security_id : item.security_id
      { segment: segment, security_id: security_id.to_s }
    else
      # Fallback to item's own segment/security_id if no watchable
      { segment: item.segment, security_id: item.security_id.to_s }
    end
  end

  hub.subscribe_many(pairs)
  ServiceTestHelper.print_success("Subscribed to #{pairs.count} instruments")
  ServiceTestHelper.print_info("Subscribed pairs:\n#{ServiceTestHelper.format_hash(pairs.to_h { |p| [p[:segment], p[:security_id]] })}")
else
  ServiceTestHelper.print_warning('No active watchlist items found')
end

# Test 4: Verify TickCache can retrieve LTP
ServiceTestHelper.print_section('4. TickCache LTP Retrieval')
ServiceTestHelper.wait_for(5, 'Waiting for ticks to arrive')

test_pairs = watchlist_items.limit(3)
if test_pairs.any?
  test_pairs.each do |item|
    watchable = item.watchable
    seg = watchable.respond_to?(:exchange_segment) ? watchable.exchange_segment : item.segment
    sid = watchable.respond_to?(:security_id) ? watchable.security_id : item.security_id
    symbol = watchable.respond_to?(:symbol_name) ? watchable.symbol_name : (item.label || item.security_id)
    ltp = tick_cache.ltp(seg, sid.to_s)

    # If no LTP in cache, fetch from DhanHQ API
    unless ltp&.positive?
      api_ltp = ServiceTestHelper.fetch_ltp(segment: seg, security_id: sid.to_s)
      if api_ltp
        ltp = api_ltp
        ServiceTestHelper.print_info("Fetched LTP from DhanHQ API for #{symbol}")
      end
    end

    if ltp&.positive?
      ServiceTestHelper.print_success("#{symbol} (#{seg}:#{sid}): LTP = ₹#{ltp}")
    else
      ServiceTestHelper.print_warning("#{symbol} (#{seg}:#{sid}): No LTP available")
    end
  end
else
  ServiceTestHelper.print_warning('No watchlist items to test')
end

# Test 5: Check tick statistics
ServiceTestHelper.print_section('5. Tick Statistics')
# Try to get tick count from cache
all_ticks = begin
  tick_cache.instance_variable_get(:@map)
rescue StandardError
  nil
end
tick_count = all_ticks ? all_ticks.size : 0
ServiceTestHelper.print_info("Total ticks in cache: #{tick_count}")

# Test 6: Sample tick data
ServiceTestHelper.print_section('6. Sample Tick Data')
if all_ticks && tick_count.positive?
  sample_key = all_ticks.keys.first
  sample_tick = all_ticks[sample_key]
  ServiceTestHelper.print_info("Sample tick (#{sample_key}):")
  puts ServiceTestHelper.format_hash(sample_tick)
else
  ServiceTestHelper.print_info('No ticks in cache yet')
end

# Test 7: Cleanup
ServiceTestHelper.print_section('7. Cleanup')
at_exit do
  hub.stop! if hub.running?
  ServiceTestHelper.print_info('MarketFeedHub stopped')
end

ServiceTestHelper.print_success('MarketFeedHub test completed')
ServiceTestHelper.print_info('Note: MarketFeedHub continues running (managed by TradingSupervisor)')
ServiceTestHelper.print_info('Do not stop it manually - it will be stopped by supervisor on shutdown')
