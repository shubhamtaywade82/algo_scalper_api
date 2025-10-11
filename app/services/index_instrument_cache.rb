# frozen_string_literal: true

class IndexInstrumentCache
    include Singleton

    CACHE_DURATION = 1.hour

    def initialize
      @cache = {}
      @cache_timestamps = {}
    end

    def get_or_fetch(index_cfg)
      cache_key = "#{index_cfg[:key]}_#{index_cfg[:sid]}_#{index_cfg[:segment]}"

      # Return cached instrument if still valid
      if cached?(cache_key)
        Rails.logger.debug("[IndexCache] Using cached instrument for #{index_cfg[:key]} (#{index_cfg[:segment]})")
        return @cache[cache_key]
      end

      # Fetch and cache the instrument
      instrument = fetch_instrument(index_cfg)
      if instrument
        @cache[cache_key] = instrument
        @cache_timestamps[cache_key] = Time.current
        Rails.logger.info("[IndexCache] Cached instrument for #{index_cfg[:key]} (#{index_cfg[:segment]}): #{instrument.symbol_name}")
      end

      instrument
    end

    def clear_cache(index_cfg = nil)
      if index_cfg
        cache_key = "#{index_cfg[:key]}_#{index_cfg[:sid]}_#{index_cfg[:segment]}"
        @cache.delete(cache_key)
        @cache_timestamps.delete(cache_key)
        Rails.logger.info("[IndexCache] Cleared cache for #{index_cfg[:key]} (#{index_cfg[:segment]})")
      else
        @cache.clear
        @cache_timestamps.clear
        Rails.logger.info("[IndexCache] Cleared all cached instruments")
      end
    end

    def cache_stats
      {
        cached_count: @cache.size,
        cache_keys: @cache.keys,
        oldest_cache: @cache_timestamps.values.min,
        newest_cache: @cache_timestamps.values.max
      }
    end

    private

    def cached?(cache_key)
      return false unless @cache[cache_key] && @cache_timestamps[cache_key]

      Time.current - @cache_timestamps[cache_key] < CACHE_DURATION
    end

    def fetch_instrument(index_cfg)
      # Try to find existing instrument in database first using both security_id and segment
      instrument = Instrument.find_by(
        security_id: index_cfg[:sid],
        segment: "index"
      )

      if instrument
        Rails.logger.debug("[IndexCache] Found existing instrument in DB: #{instrument.symbol_name} (#{instrument.segment})")
        return instrument
      end

      # If not found, create a temporary instrument object with the config
      Rails.logger.info("[IndexCache] Creating temporary instrument for #{index_cfg[:key]} (SID: #{index_cfg[:sid]}, Segment: #{index_cfg[:segment]})")

      Instrument.new(
        security_id: index_cfg[:sid],
        symbol_name: index_cfg[:key],
        exchange: determine_exchange(index_cfg[:segment]),
        segment: "index",
        instrument_code: "index",
        enabled: true
      )
    end

    def determine_exchange(segment)
      case segment
      when "IDX_I"
        "NSE" # Default to NSE for index instruments
      when "BSE_EQ"
        "BSE"
      when "NSE_EQ"
        "NSE"
      else
        "NSE" # Default fallback
      end
    end
end
