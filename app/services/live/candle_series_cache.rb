# frozen_string_literal: true

module Live
  # Redis-backed CandleSeries cache.
  #
  # Provides a unified {CandleSeries} that merges backfilled historical candles
  # (fetched on demand from DhanHQ) with live WebSocket ticks, so indicator
  # calculations always have a continuous, up-to-date series.
  #
  # Key format:  `live:candles:<security_id>:<interval>`
  # Value:       JSON string (see {SCHEMA} comment below)
  # TTL:         3600 s — auto-expires after market close
  #
  # @example Fetch or build a series for indicators
  #   series = Live::CandleSeriesCache.fetch(instrument: nifty, interval: 5)
  #   series.rsi(14)  #=> Float
  #
  # @example Append a live tick to the forming candle
  #   Live::CandleSeriesCache.append_tick(instrument: nifty, tick: tick_hash, interval: 5)
  #
  # @example Force full refresh
  #   Live::CandleSeriesCache.refresh(instrument: nifty, interval: 5)
  class CandleSeriesCache
    REDIS_KEY_PREFIX = "live:candles"
    TTL_SECONDS      = 3_600
    MIN_CANDLES      = 20
    MAX_CANDLES      = CandleSeries::MAX_CANDLES # 200

    # JSON schema stored per key:
    # {
    #   "updated_at": <unix timestamp>,
    #   "candles": [
    #     { "timestamp": "2026-06-19T09:15:00.000Z",
    #       "open": 24500.0, "high": 24520.0, "low": 24495.0, "close": 24510.0,
    #       "volume": 12500, "oi": 0 }
    #   ]
    # }

    class << self
      # Fetch or build a CandleSeries for the given instrument and interval.
      #
      # If the cached series has fewer than {MIN_CANDLES} candles and +backfill:+ is
      # true, {Live::HistoricalBackfillService} is invoked before returning.
      #
      # @param instrument [Instrument]
      # @param interval [Integer] candle interval in minutes
      # @param backfill [Boolean] auto-backfill when cache is thin
      # @return [CandleSeries, nil]
      def fetch(instrument:, interval: 5, backfill: true)
        raw = redis.get(redis_key(instrument.security_id, interval))
        parsed = raw ? JSON.parse(raw) : nil

        candles = parsed&.dig("candles") || []

        if candles.size < MIN_CANDLES && backfill
          trigger_backfill(instrument, interval)
          raw = redis.get(redis_key(instrument.security_id, interval))
          parsed = raw ? JSON.parse(raw) : nil
          candles = parsed&.dig("candles") || []
        end

        return nil if candles.empty?

        build_candle_series(instrument, interval, candles)
      rescue JSON::ParserError => e
        Rails.logger.warn("[CandleSeriesCache] JSON parse error for #{instrument.security_id}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.error("[CandleSeriesCache] fetch error for #{instrument.security_id}: #{e.class} - #{e.message}")
        nil
      end

      # Force a full refresh: bust the cache, re-fetch from DhanHQ, return new series.
      #
      # @param instrument [Instrument]
      # @param interval [Integer]
      # @return [CandleSeries, nil]
      def refresh(instrument:, interval: 5)
        redis.del(redis_key(instrument.security_id, interval))
        trigger_backfill(instrument, interval)
        fetch(instrument: instrument, interval: interval, backfill: false)
      end

      # Append a live tick to the forming candle for the given interval.
      #
      # Updates the current open candle: open is preserved, high/low/close adjust
      # to the new LTP, and volume increments. Safe to call on every WebSocket tick.
      # O(2) Redis ops (GET + SET), typically < 1 ms.
      #
      # @param instrument [Instrument]
      # @param tick [Hash] tick hash with +:ltp+, +:oi+, +:volume+ keys
      # @param interval [Integer]
      # @return [void]
      def append_tick(instrument:, tick:, interval: 5)
        ltp = tick[:ltp].to_f
        return unless ltp.positive?

        key = redis_key(instrument.security_id, interval)
        raw = redis.get(key)

        now     = Time.current
        bucket  = bucket_ts(now, interval)
        bucket_iso = Time.at(bucket).utc.iso8601(3)

        data = raw ? JSON.parse(raw) : { "updated_at" => now.to_i, "candles" => [] }

        candles = data["candles"]
        last    = candles.last

        if last && last["timestamp"] == bucket_iso
          # Update the forming candle in place
          last["high"]   = [last["high"].to_f, ltp].max
          last["low"]    = [last["low"].to_f, ltp].min
          last["close"]  = ltp
          last["volume"] = last["volume"].to_i + tick[:volume].to_i
          last["oi"]     = tick[:oi].to_i if tick[:oi].to_i.positive?
        else
          # The previous forming candle (if any) is now finalized — hand it off
          # for durable persistence before starting the new one. A persistence
          # hiccup must never block or abort the Redis write below.
          begin
            Candles::Persister.enqueue(instrument: instrument, interval: interval, candles: [last], source: "live") if last
          rescue StandardError => e
            Rails.logger.error("[CandleSeriesCache] append_tick persist enqueue error: #{e.class} - #{e.message}")
          end

          # Start a new forming candle
          new_candle = {
            "timestamp" => bucket_iso,
            "open" => ltp,
            "high" => ltp,
            "low" => ltp,
            "close" => ltp,
            "volume" => tick[:volume].to_i,
            "oi" => tick[:oi].to_i
          }
          candles << new_candle
          # Enforce max candles — drop oldest
          candles.shift while candles.size > MAX_CANDLES
        end

        data["updated_at"] = now.to_i
        redis.set(key, data.to_json, ex: TTL_SECONDS)
      rescue JSON::ParserError => e
        Rails.logger.warn("[CandleSeriesCache] append_tick JSON error for #{instrument&.security_id}: #{e.message}")
        redis.del(key) if key
      rescue StandardError => e
        Rails.logger.error("[CandleSeriesCache] append_tick error: #{e.class} - #{e.message}")
      end

      # Persist a set of raw candle hashes directly into the cache.
      # Called by {HistoricalBackfillService} after fetching DhanHQ data.
      #
      # @param security_id [String]
      # @param interval [Integer]
      # @param candles [Array<Hash>] normalised candle hashes
      # @return [void]
      def store_candles(security_id:, interval:, candles:)
        return if candles.blank?

        key = redis_key(security_id, interval)
        raw = redis.get(key)
        existing = raw ? JSON.parse(raw)["candles"] : []

        # Merge: use timestamp as dedup key, prefer newer data
        by_ts = existing.index_by { |c| c["timestamp"] }
        candles.each do |c|
          ts = normalise_ts(c[:timestamp] || c["timestamp"])
          next unless ts

          by_ts[ts] = {
            "timestamp" => ts,
            "open" => c[:open].to_f,
            "high" => c[:high].to_f,
            "low" => c[:low].to_f,
            "close" => c[:close].to_f,
            "volume" => c[:volume].to_i,
            "oi" => c[:oi].to_i
          }
        end

        merged = by_ts.values.sort_by { |c| c["timestamp"] }.last(MAX_CANDLES)
        payload = { "updated_at" => Time.current.to_i, "candles" => merged }
        redis.set(key, payload.to_json, ex: TTL_SECONDS)
      rescue JSON::ParserError
        # Corrupted cache — overwrite fresh
        redis.del(key)
      rescue StandardError => e
        Rails.logger.error("[CandleSeriesCache] store_candles error: #{e.class} - #{e.message}")
      end

      private

      def trigger_backfill(instrument, interval)
        Live::HistoricalBackfillService.new.backfill(
          instrument: instrument,
          interval: interval,
          reason: :warmup
        )
      end

      def build_candle_series(instrument, interval, candles)
        series = CandleSeries.new(symbol: instrument.symbol_name, interval: interval.to_s)
        candles.each do |c|
          series.add_candle(
            Candle.new(
              timestamp: parse_ts(c["timestamp"]),
              open: c["open"].to_f,
              high: c["high"].to_f,
              low: c["low"].to_f,
              close: c["close"].to_f,
              volume: c["volume"].to_i
            )
          )
        end
        series.ensure_sorted!
        series
      end

      def redis_key(security_id, interval)
        "#{REDIS_KEY_PREFIX}:#{security_id}:#{interval}"
      end

      def bucket_ts(time, interval)
        t = time.to_i
        t - (t % (interval * 60))
      end

      def normalise_ts(raw)
        return nil unless raw

        t = raw.is_a?(Time) || raw.is_a?(ActiveSupport::TimeWithZone) ? raw : Time.zone.parse(raw.to_s)
        t.utc.iso8601(3)
      rescue ArgumentError, TypeError
        nil
      end

      def parse_ts(raw)
        return raw if raw.is_a?(Time) || raw.is_a?(ActiveSupport::TimeWithZone)

        Time.zone.parse(raw.to_s)
      rescue ArgumentError, TypeError
        Time.current
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
      end
    end
  end
end
