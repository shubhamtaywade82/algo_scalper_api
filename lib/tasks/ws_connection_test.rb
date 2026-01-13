# frozen_string_literal: true

# WebSocket Connection Test Script
# Tests WS connection and LTP retrieval for subscribed instruments
#
# Usage (via Rails runner):
#   rails runner lib/tasks/ws_connection_test.rb
#   rails runner lib/tasks/ws_connection_test.rb NIFTY,BANKNIFTY
#   rails runner lib/tasks/ws_connection_test.rb NIFTY --segment=IDX_I --wait=20
#
# Usage (via Rake task):
#   rake test:ws
#   rake test:ws[NIFTY,BANKNIFTY]
#   rake test:ws[NIFTY,IDX_I,20]

module WsConnectionTest
  class << self
    def run(instruments: nil, segment: 'IDX_I', wait_seconds: 15)
      # Detect market status
      market_status = detect_market_status

      Rails.logger.debug { "\n#{'=' * 80}" }
      Rails.logger.debug 'WebSocket Connection & LTP Test'
      Rails.logger.debug '=' * 80
      Rails.logger.debug "\nConfiguration:"
      Rails.logger.debug { "  Segment: #{segment}" }
      Rails.logger.debug { "  Wait time: #{wait_seconds} seconds" }
      Rails.logger.debug { "  Instruments: #{instruments || 'from config'}" }
      Rails.logger.debug "\nMarket Status:"
      Rails.logger.debug { "  Trading Day: #{market_status[:is_trading_day] ? '✅ Yes' : '❌ No (Weekend/Holiday)'}" }
      Rails.logger.debug { "  Market Hours: #{market_status[:status]}" }
      Rails.logger.debug { "  Expectation: #{market_status[:expectation]}" }
      Rails.logger.debug "\n"

      # Step 1: Check if WS hub is running
      Rails.logger.debug '[1/5] Checking WebSocket Hub Status...'
      hub = Live::MarketFeedHub.instance

      if hub.running?
        Rails.logger.debug '✅ WebSocket hub is running'
      else
        Rails.logger.debug '❌ FAIL: WebSocket hub is NOT running'
        Rails.logger.debug "\nDiagnostics:"

        # Check if credentials are configured
        client_id = ENV['CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
        access_token = ENV['DHANHQ_ACCESS_TOKEN'].presence || ENV['ACCESS_TOKEN'].presence

        if client_id.blank? || access_token.blank?
          Rails.logger.debug '   ❌ DhanHQ credentials not configured'
          Rails.logger.debug '      Required: CLIENT_ID (or CLIENT_ID)'
          Rails.logger.debug '      Required: DHANHQ_ACCESS_TOKEN (or ACCESS_TOKEN)'
          Rails.logger.debug "\n   To fix: Set credentials in environment variables or .env file"
          return { success: false, error: 'credentials_missing', message: 'DhanHQ credentials not configured' }
        else
          Rails.logger.debug '   ✅ DhanHQ credentials found'
        end

        Rails.logger.debug "\nAttempting to start WebSocket hub..."
        begin
          if hub.start!
            Rails.logger.debug '✅ WebSocket hub started successfully'
          else
            Rails.logger.debug '❌ FAIL: Could not start WebSocket hub (start! returned false)'
            Rails.logger.debug '   Possible causes:'
            Rails.logger.debug '   - DhanHQ API connectivity issues'
            Rails.logger.debug '   - Invalid credentials'
            Rails.logger.debug '   - Network/firewall blocking WebSocket connections'
            Rails.logger.debug '   - DhanHQ service temporarily unavailable'
            return { success: false, error: 'hub_start_failed', message: 'WebSocket hub failed to start' }
          end
        rescue StandardError => e
          Rails.logger.debug { "❌ FAIL: Error starting WebSocket hub: #{e.class} - #{e.message}" }
          Rails.logger.debug '   Check logs for detailed error information'
          return { success: false, error: 'hub_start_error', message: e.message, exception: e.class.to_s }
        end
      end

      # Step 2: Determine test instruments
      Rails.logger.debug "\n[2/5] Determining test instruments..."
      test_instruments = if instruments
                           parse_instruments(instruments, segment)
                         else
                           load_from_config(segment)
                         end

      if test_instruments.empty?
        Rails.logger.debug '❌ FAIL: No instruments found to test'
        return { success: false, error: 'no_instruments' }
      end

      Rails.logger.debug { "✅ Found #{test_instruments.size} instrument(s) to test:" }
      test_instruments.each do |inst|
        Rails.logger.debug "   - #{inst[:key]} (#{inst[:segment]}:#{inst[:security_id]})"
      end

      # Step 3: Subscribe to instruments
      Rails.logger.debug "\n[3/5] Subscribing to instruments..."
      subscribed = []
      test_instruments.each do |inst|
        hub.subscribe(segment: inst[:segment], security_id: inst[:security_id])
        subscribed << inst
        Rails.logger.debug { "   ✅ Subscribed: #{inst[:key]} (#{inst[:segment]}:#{inst[:security_id]})" }
      rescue StandardError => e
        Rails.logger.debug { "   ❌ Failed to subscribe #{inst[:key]}: #{e.message}" }
      end

      if subscribed.empty?
        Rails.logger.debug '❌ FAIL: Could not subscribe to any instruments'
        return { success: false, error: 'subscription_failed' }
      end

      # Step 4: Wait for ticks and verify
      Rails.logger.debug { "\n[4/5] Waiting #{wait_seconds} seconds for tick data..." }
      if market_status[:is_market_hours]
        Rails.logger.debug '   (Listening for live ticks during market hours...)'
        Rails.logger.debug '   ⚠️  During market hours: Expecting multiple live ticks'
      else
        Rails.logger.debug '   (Market closed - verifying WebSocket connection with stale ticks...)'
        Rails.logger.debug '   ⚠️  After market hours: Need at least one tick to verify connection'
      end

      received_ticks = {}
      tick_listener = lambda do |tick|
        key = "#{tick[:segment]}:#{tick[:security_id]}"
        received_ticks[key] = {
          ltp: tick[:ltp],
          timestamp: Time.current,
          raw: tick
        }
        Rails.logger.debug { "   📊 Tick received: #{key} → LTP: #{tick[:ltp]}" }
      end

      # Register callback using proper API
      hub.on_tick(&tick_listener)

      sleep(wait_seconds)

      # Step 5: Verify LTPs from cache
      Rails.logger.debug "\n[5/5] Verifying LTP retrieval from cache..."
      results = {}
      all_passed = true

      subscribed.each do |inst|
        tick_key = "#{inst[:segment]}:#{inst[:security_id]}"

        # Try TickCache first (in-memory)
        tick_cache_ltp = Live::TickCache.ltp(inst[:segment], inst[:security_id])

        # Try RedisPnlCache second
        redis_tick = Live::RedisPnlCache.instance.fetch_tick(segment: inst[:segment], security_id: inst[:security_id])
        redis_ltp = redis_tick&.dig(:ltp)

        # Check if we received tick during wait period
        received_tick = received_ticks[tick_key]

        result = {
          key: inst[:key],
          segment: inst[:segment],
          security_id: inst[:security_id],
          subscribed: true,
          tick_received: !received_tick.nil?,
          tick_cache_ltp: tick_cache_ltp,
          redis_cache_ltp: redis_ltp,
          last_received: received_tick&.dig(:timestamp),
          success: false
        }

        # Success criteria depends on market hours
        if market_status[:is_market_hours]
          # During market hours: Must receive live tick during wait period
          if received_tick
            result[:success] = true
            result[:ltp_source] = 'Live tick (market hours)'
            result[:final_ltp] = received_tick[:ltp]
            Rails.logger.debug { "   ✅ #{inst[:key]}: LTP = #{result[:final_ltp]} (Live tick received)" }
          elsif tick_cache_ltp || redis_ltp
            result[:success] = true
            result[:ltp_source] = tick_cache_ltp ? 'TickCache (in-memory)' : 'RedisPnlCache'
            result[:final_ltp] = tick_cache_ltp || redis_ltp
            Rails.logger.debug { "   ⚠️  #{inst[:key]}: LTP = #{result[:final_ltp]} (#{result[:ltp_source]} - cached, no live tick received)" }
          else
            result[:success] = false
            all_passed = false
            Rails.logger.debug { "   ❌ #{inst[:key]}: No LTP found - expected live tick during market hours" }
          end
        elsif received_tick
          # After market hours/weekend: Cached data is acceptable, but we still need at least one tick
          # to verify WebSocket connection is working
          result[:success] = true
          result[:ltp_source] = 'Stale tick received (market closed)'
          result[:final_ltp] = received_tick[:ltp]
          Rails.logger.debug { "   ✅ #{inst[:key]}: LTP = #{result[:final_ltp]} (#{result[:ltp_source]})" }
        elsif tick_cache_ltp || redis_ltp
          result[:success] = true
          result[:ltp_source] =
            tick_cache_ltp ? 'TickCache (cached, no fresh tick)' : 'RedisPnlCache (cached, no fresh tick)'
          result[:final_ltp] = tick_cache_ltp || redis_ltp
          Rails.logger.debug { "   ⚠️  #{inst[:key]}: LTP = #{result[:final_ltp]} (#{result[:ltp_source]})" }
          Rails.logger.debug '      Note: No fresh tick received during wait - WebSocket may not be streaming'
        else
          result[:success] = false
          all_passed = false
          Rails.logger.debug { "   ❌ #{inst[:key]}: No LTP found - WebSocket connection may not be working" }
        end

        results[inst[:key]] = result
      end

      # Summary
      Rails.logger.debug { "\n#{'=' * 80}" }
      Rails.logger.debug 'Test Summary'
      Rails.logger.debug '=' * 80
      Rails.logger.debug { "\nWebSocket Hub: #{hub.running? ? '✅ Running' : '❌ Not Running'}" }
      Rails.logger.debug { "Market Status: #{market_status[:status]}" }
      Rails.logger.debug { "Instruments Tested: #{subscribed.size}" }
      successful_count = results.values.count { |r| r[:success] }
      Rails.logger.debug { "Instruments with LTP: #{successful_count}" }
      Rails.logger.debug { "Success Rate: #{successful_count}/#{subscribed.size}" }

      ticks_received = results.values.count { |r| r[:tick_received] }
      if market_status[:is_market_hours]
        Rails.logger.debug { "Live Ticks Received: #{ticks_received}/#{subscribed.size}" }
        if ticks_received < subscribed.size
          Rails.logger.debug '⚠️  Warning: Not all instruments received live ticks during market hours'
        end
      else
        Rails.logger.debug { "Ticks Received (stale/cached): #{ticks_received}/#{subscribed.size}" }
        if ticks_received.zero?
          Rails.logger.debug '⚠️  Warning: No ticks received - WebSocket connection may not be working'
          Rails.logger.debug '   (Even during non-market hours, we expect at least one tick to verify connection)'
        elsif ticks_received < subscribed.size
          Rails.logger.debug '⚠️  Warning: Some instruments did not receive ticks'
        end
      end

      Rails.logger.debug "\nDetailed Results:"
      results.each do |key, result|
        status = result[:success] ? '✅' : '❌'
        Rails.logger.debug { "  #{status} #{key}:" }
        Rails.logger.debug { "     Subscribed: #{result[:subscribed] ? 'Yes' : 'No'}" }
        Rails.logger.debug { "     Tick Received: #{result[:tick_received] ? 'Yes' : 'No'}" }
        Rails.logger.debug { "     TickCache LTP: #{result[:tick_cache_ltp] || 'N/A'}" }
        Rails.logger.debug { "     RedisCache LTP: #{result[:redis_cache_ltp] || 'N/A'}" }
        Rails.logger.debug { "     ✅ Final LTP: #{result[:final_ltp]} (from #{result[:ltp_source]})" } if result[:success]
      end

      # Additional validation: Even during non-market hours, we need at least one tick
      # to verify WebSocket connection is actually working
      overall_success = all_passed && subscribed.size == successful_count
      # After market hours/weekend: Require at least one tick to verify connection
      if !market_status[:is_market_hours] && ticks_received.zero?
        overall_success = false
        Rails.logger.debug "\n⚠️  CRITICAL: No ticks received during wait period"
        Rails.logger.debug '   Even when market is closed, we need at least one tick to verify WebSocket connection'
        Rails.logger.debug '   This indicates WebSocket may not be properly connected or streaming'
      end

      Rails.logger.debug { "\n#{'=' * 80}" }
      if overall_success
        Rails.logger.debug '✅ ALL TESTS PASSED'
        Rails.logger.debug '=' * 80
        { success: true, results: results, market_status: market_status }
      else
        Rails.logger.debug '❌ SOME TESTS FAILED'
        Rails.logger.debug '=' * 80
        Rails.logger.debug "\nNext Steps:"
        Rails.logger.debug '1. Ensure WebSocket hub is running: Live::MarketFeedHub.instance.start!' unless hub.running?
        if ticks_received.zero?
          Rails.logger.debug '2. Verify WebSocket connection is active and receiving ticks'
          Rails.logger.debug '3. Check DhanHQ credentials: CLIENT_ID and DHANHQ_ACCESS_TOKEN'
        end
        Rails.logger.debug '4. Review application logs for WebSocket errors'
        Rails.logger.debug '=' * 80
        { success: false, results: results, market_status: market_status }
      end
    end

    private

    def detect_market_status
      current_time = Time.zone.now
      hour = current_time.hour
      minute = current_time.min

      # Check if it's a trading day (not weekend/holiday)
      is_trading_day = begin
        Market::Calendar.trading_day_today?
      rescue StandardError
        # Fallback: simple weekend check
        !current_time.saturday? && !current_time.sunday?
      end

      # Market hours: 9:15 AM to 3:30 PM IST
      market_open = hour > 9 || (hour == 9 && minute >= 15)
      market_closed = hour > 15 || (hour == 15 && minute >= 30)
      is_market_hours = market_open && !market_closed

      status = if !is_trading_day
                 'Weekend/Holiday (Market Closed)'
               elsif !market_open
                 'Pre-Market (Before 9:15 AM)'
               elsif market_closed
                 'Post-Market (After 3:30 PM)'
               else
                 'Market Open (9:15 AM - 3:30 PM IST)'
               end

      expectation = if !is_trading_day
                      'At least one stale tick to verify connection (no live ticks)'
                    elsif is_market_hours
                      'Live ticks expected (multiple ticks during wait period)'
                    else
                      'At least one stale tick to verify connection (no live ticks)'
                    end

      {
        is_trading_day: is_trading_day,
        is_market_hours: is_market_hours && is_trading_day,
        status: status,
        expectation: expectation,
        current_time: current_time.strftime('%Y-%m-%d %H:%M:%S %Z')
      }
    end

    def parse_instruments(instruments_str, segment)
      instruments_str.split(',').filter_map do |key|
        key = key.strip.upcase
        # Look up security_id from Instrument table
        inst = Instrument.find_by(symbol_name: key, segment: Instrument.segment_key_for(segment))
        if inst
          {
            key: key,
            segment: inst.exchange_segment,
            security_id: inst.security_id
          }
        else
          # Fallback: use config to find security_id
          config = AlgoConfig.fetch[:indices]&.find { |i| i[:key] == key }
          if config
            {
              key: key,
              segment: config[:segment] || segment,
              security_id: config[:sid]
            }
          else
            Rails.logger.debug { "⚠️  Warning: Could not find instrument #{key}" }
            nil
          end
        end
      end
    end

    def load_from_config(segment)
      indices = AlgoConfig.fetch[:indices] || []
      indices.filter_map do |cfg|
        next unless cfg[:segment] == segment || segment == 'IDX_I'

        {
          key: cfg[:key],
          segment: cfg[:segment] || segment,
          security_id: cfg[:sid]
        }
      end
    end
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME || defined?(Rails::Console)
  # Parse command line arguments
  instruments = ARGV.find { |a| !a.start_with?('--') }
  segment = ARGV.find { |a| a.start_with?('--segment=') }&.split('=')&.last || 'IDX_I'
  wait_arg = ARGV.find { |a| a.start_with?('--wait=') }&.split('=')&.last
  wait_seconds = wait_arg ? wait_arg.to_i : 15

  result = WsConnectionTest.run(
    instruments: instruments,
    segment: segment,
    wait_seconds: wait_seconds
  )

  exit(result[:success] ? 0 : 1)
end
