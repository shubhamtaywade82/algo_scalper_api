# frozen_string_literal: true

require 'singleton'

module Paper
  # Throttled LTP fetcher for paper mode when WebSocket isn't available
  # Caches results and prevents fetching more than once per 30 seconds per instrument
  class LtpFetcher
    include Singleton

    FETCH_INTERVAL_SECONDS = 30
    CACHE_KEY_PREFIX = 'paper:ltp_fetch:'

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    rescue StandardError => e
      Rails.logger.error("Failed to initialize Paper::LtpFetcher Redis: #{e.message}")
      @redis = nil
    end

    # Get LTP with throttling - returns cached value if fetched recently
    # @param segment [String] Exchange segment
    # @param security_id [String] Security ID
    # @return [Float, nil] LTP or nil if unavailable
    def fetch_ltp(segment:, security_id:)
      cache_key = cache_key(segment, security_id)

      # Check if we have a cached value
      cached = fetch_cached(cache_key)
      return cached if cached

      # Throttle: don't fetch if last fetch was < 30 seconds ago
      last_fetch_time = get_last_fetch_time(cache_key)
      if last_fetch_time && (Time.current.to_i - last_fetch_time) < FETCH_INTERVAL_SECONDS
        age = Time.current.to_i - last_fetch_time
        Rails.logger.debug { "[Paper::LtpFetcher] Throttled: #{segment}:#{security_id} (last fetch #{age}s ago, need #{FETCH_INTERVAL_SECONDS}s)" }
        return nil # Return nil to indicate we should wait
      end

      # Fetch LTP from API
      ltp = fetch_from_api(segment, security_id)

      # Cache the result (even if nil) with timestamp
      if ltp
        cache_result(cache_key, ltp)
      else
        mark_fetch_attempt(cache_key) # Record that we tried, even if failed
      end

      ltp
    rescue StandardError => e
      Rails.logger.error("[Paper::LtpFetcher] Error fetching LTP: #{e.class} - #{e.message}")
      nil
    end

    private

    def fetch_from_api(segment, security_id)
      Rails.logger.info("[Paper::LtpFetcher] Fetching LTP from API for #{segment}:#{security_id} (throttled: 30s min interval)")

      instrument = Instrument.find_by(security_id: security_id.to_s)
      unless instrument
        Rails.logger.error("[Paper::LtpFetcher] Instrument not found for security_id: #{security_id}")
        return nil
      end

      # Use DhanHQ MarketFeed.ltp API (same as Instrument#fetch_ltp_from_api)
      begin
        # Use instrument's exch_segment_enum method which returns { exchange_segment => [security_id.to_i] }
        exch_enum = instrument.exch_segment_enum
        Rails.logger.debug { "[Paper::LtpFetcher] Calling MarketFeed.ltp with: #{exch_enum.inspect}" }
        response = DhanHQ::Models::MarketFeed.ltp(exch_enum)

        Rails.logger.debug { "[Paper::LtpFetcher] API response status: #{response['status']}" }

        if response['status'] == 'success'
          exch_segment = instrument.exchange_segment
          Rails.logger.debug { "[Paper::LtpFetcher] Looking for LTP in response['data']['#{exch_segment}']['#{security_id}']" }

          ltp_data = response.dig('data', exch_segment, security_id.to_s)

          if ltp_data.nil?
            # Try with integer key
            ltp_data = response.dig('data', exch_segment, security_id.to_i.to_s)
          end

          if ltp_data.nil?
            Rails.logger.warn("[Paper::LtpFetcher] No data found in response. Response keys: #{response.dig('data')&.keys&.inspect}")
            Rails.logger.warn("[Paper::LtpFetcher] Full response structure: #{response.inspect}")
          elsif ltp_data['last_price']
            ltp = ltp_data['last_price'].to_f
            Rails.logger.info("[Paper::LtpFetcher] Fetched LTP from API: #{segment}:#{security_id} = #{ltp}")
            return ltp
          else
            Rails.logger.warn("[Paper::LtpFetcher] LTP data found but no 'last_price' key: #{ltp_data.keys.inspect}")
          end
        else
          Rails.logger.error("[Paper::LtpFetcher] API response failed: #{response['message'] || response.inspect}")
        end
      rescue StandardError => e
        Rails.logger.error("[Paper::LtpFetcher] MarketFeed API fetch failed: #{e.class} - #{e.message}")
        Rails.logger.error("[Paper::LtpFetcher] Backtrace: #{e.backtrace.first(5).join(', ')}")
      end

      nil
    end

    def cache_key(segment, security_id)
      "#{CACHE_KEY_PREFIX}#{segment}:#{security_id}"
    end

    def fetch_cached(cache_key)
      return nil unless @redis

      data = @redis.hgetall(cache_key)
      return nil if data.empty?

      ltp = data['ltp']&.to_f
      timestamp = data['timestamp']&.to_i

      # Return cached value if it's fresh (< 30 seconds old)
      if ltp && timestamp && (Time.current.to_i - timestamp) < FETCH_INTERVAL_SECONDS
        Rails.logger.debug { "[Paper::LtpFetcher] Using cached LTP: #{ltp} (age: #{Time.current.to_i - timestamp}s)" }
        return ltp
      end

      nil
    end

    def get_last_fetch_time(cache_key)
      return nil unless @redis

      data = @redis.hgetall(cache_key)
      data['timestamp']&.to_i
    end

    def cache_result(cache_key, ltp)
      return unless @redis

      @redis.hset(cache_key, {
                    'ltp' => ltp.to_s,
                    'timestamp' => Time.current.to_i
                  })
      @redis.expire(cache_key, FETCH_INTERVAL_SECONDS * 2) # Keep cache for 2x interval
    end

    def mark_fetch_attempt(cache_key)
      return unless @redis

      @redis.hset(cache_key, {
                    'timestamp' => Time.current.to_i
                  })
      @redis.expire(cache_key, FETCH_INTERVAL_SECONDS * 2)
    end
  end
end
