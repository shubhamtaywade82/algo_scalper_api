# frozen_string_literal: true

module Live
  # On-demand historical OHLC backfill service.
  #
  # Detects gaps in the Redis tick store (reconnect, new instrument, explicit request)
  # and fetches missing OHLC candles from DhanHQ `POST /v2/charts/intraday`.
  # Each fetched candle is translated into two synthetic ticks (open + close) and
  # written via {OptionsBuying::StateStore.append_minute_tick}, so downstream
  # consumers ({OptionsBuying::BreakoutEvaluator}) need zero changes.
  #
  # @example Reconnect gap recovery
  #   Live::HistoricalBackfillService.new.backfill_all(interval: 1)
  #
  # @example Warm-up a newly subscribed radar strike
  #   from = (Time.current - 30.minutes).strftime("%Y-%m-%d %H:%M:%S")
  #   Live::HistoricalBackfillService.new.backfill(instrument: instrument, interval: 1,
  #                                                from_date: from, reason: :warmup)
  class HistoricalBackfillService
    # Maximum number of candles fetched in a single call. Keeps Redis lean.
    MAX_CANDLES_PER_BACKFILL = 100

    # Minimum gap (in minutes) before a backfill is considered worthwhile.
    MISSING_MINUTES_THRESHOLD = 5

    # Seconds between successive DhanHQ data-API requests (1 req / 2 s).
    RATE_LIMIT_INTERVAL = 2

    # Retry count on transient DhanHQ errors.
    MAX_RETRIES = 1

    # Consecutive failures before the circuit breaker trips.
    CIRCUIT_BREAKER_THRESHOLD = 3

    # How long (seconds) the circuit breaker pauses after tripping.
    CIRCUIT_BREAKER_PAUSE = 60

    # Redis keys
    RATE_TS_KEY      = "live:backfill:rate_ts"
    FAILURE_CTR_KEY  = "live:backfill:failures"
    CIRCUIT_OPEN_KEY = "live:backfill:circuit_open"

    # -------------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------------

    # Fetch historical candles for a single instrument and hydrate Redis.
    #
    # @param instrument [Instrument] ActiveRecord instrument record
    # @param interval [Integer] Candle interval in minutes (1, 5, 15, 25, 60)
    # @param from_date [String, nil] "YYYY-MM-DD HH:MM:SS" start of range. Defaults to
    #   the detected gap start (or 30 minutes ago when no gap data is available).
    # @param to_date [String, nil] "YYYY-MM-DD HH:MM:SS" end of range. Defaults to now.
    # @param reason [Symbol] :reconnect | :warmup | :on_demand — for logging only
    # @return [Hash] { success: Boolean, candles_fetched: Integer,
    #                  min_bucket: Integer|nil, max_bucket: Integer|nil, error: String|nil }
    def backfill(instrument:, interval: 1, from_date: nil, to_date: nil, reason: :on_demand)
      return circuit_open_result if circuit_open?

      rate_limit_wait!

      to_date   ||= Time.current.strftime("%Y-%m-%d %H:%M:%S")
      from_date ||= detect_gap_from(instrument, interval)

      Rails.logger.info(
        "[HistoricalBackfillService] #{reason} backfill for #{instrument.security_id} " \
        "(#{instrument.symbol_name}) interval=#{interval}m from=#{from_date} to=#{to_date}"
      )

      raw = fetch_with_retry(instrument, interval, from_date, to_date)

      unless raw
        record_failure!
        return { success: false, candles_fetched: 0, min_bucket: nil, max_bucket: nil, error: "DhanHQ fetch failed" }
      end

      candles = normalize_raw(raw)
      store_result = store_candles(instrument.security_id.to_s, interval, candles)

      reset_failures!
      update_rate_ts!

      Rails.logger.info(
        "[HistoricalBackfillService] Stored #{store_result[:count]} candles for " \
        "#{instrument.security_id} (reason=#{reason})"
      )

      {
        success: true,
        candles_fetched: store_result[:count],
        min_bucket: store_result[:min_bucket],
        max_bucket: store_result[:max_bucket],
        error: nil
      }
    rescue StandardError => e
      record_failure!
      Rails.logger.error(
        "[HistoricalBackfillService] Unexpected error for #{instrument&.security_id}: #{e.class} - #{e.message}"
      )
      { success: false, candles_fetched: 0, min_bucket: nil, max_bucket: nil, error: e.message }
    end

    # Backfill all active positions and watchlist indices in sequence.
    #
    # Instruments with a gap smaller than +missing_minutes_threshold+ are skipped.
    #
    # @param interval [Integer] candle interval in minutes
    # @param missing_minutes_threshold [Integer] minimum gap to bother backfilling
    def backfill_all(interval: 1, missing_minutes_threshold: MISSING_MINUTES_THRESHOLD)
      instruments = collect_instruments_to_backfill
      Rails.logger.info("[HistoricalBackfillService] backfill_all: #{instruments.size} instruments to check")

      instruments.each do |instrument|
        next if circuit_open?
        next unless gap_large_enough?(instrument, interval, missing_minutes_threshold)

        backfill(instrument: instrument, interval: interval, reason: :reconnect)
      rescue StandardError => e
        Rails.logger.warn(
          "[HistoricalBackfillService] backfill_all skipped #{instrument&.security_id}: #{e.class} - #{e.message}"
        )
      end
    end

    private

    # -------------------------------------------------------------------------
    # Instrument collection
    # -------------------------------------------------------------------------

    def collect_instruments_to_backfill
      instruments = []

      # 1. Active position instruments
      active_trackers = begin
                          Positions::ActivePositionsCache.instance.active_trackers
      rescue StandardError
                          []
      end
      active_trackers.each do |tracker|
        inst = tracker.instrument || Instrument.find_by(security_id: tracker.security_id)
        instruments << inst if inst
      end

      # 2. Watchlist index instruments (NIFTY, BANKNIFTY, SENSEX spot)
      IndexConfigLoader.load_indices.each do |cfg|
        inst = begin
                 IndexInstrumentCache.instance.get_or_fetch(cfg)
        rescue StandardError
                 nil
        end
        instruments << inst if inst
      end

      instruments.uniq(&:security_id)
    end

    # -------------------------------------------------------------------------
    # Gap detection
    # -------------------------------------------------------------------------

    # Derive the earliest timestamp missing from the Redis tick store.
    # Falls back to 30 minutes ago when no bucket data exists at all.
    def detect_gap_from(instrument, interval)
      if %w[index i].include?(instrument.segment.to_s.downcase)
        return (Time.current - (60 * interval * 60)).strftime("%Y-%m-%d %H:%M:%S")
      end

      security_id = instrument.security_id.to_s
      now_bucket  = bucket_for(Time.current, interval)

      # Walk back until we find a bucket with data
      MAX_CANDLES_PER_BACKFILL.times do |i|
        bucket = now_bucket - ((i + 1) * interval * 60)
        ticks  = OptionsBuying::StateStore.minute_ticks(security_id, bucket)
        return Time.at(bucket).strftime("%Y-%m-%d %H:%M:%S") unless ticks.any?
      end

      # All 100 previous buckets have data — nothing to backfill
      Time.current.strftime("%Y-%m-%d %H:%M:%S")
    end

    def gap_large_enough?(instrument, interval, threshold_minutes)
      if %w[index i].include?(instrument.segment.to_s.downcase)
        raw = redis.get("live:candles:#{instrument.security_id}:#{interval}")
        return true unless raw
        begin
          parsed = JSON.parse(raw)
          return (parsed&.dig("candles") || []).size < MIN_CANDLES
        rescue StandardError
          return true
        end
      end

      security_id = instrument.security_id.to_s
      now_bucket  = bucket_for(Time.current, interval)
      threshold_buckets = threshold_minutes / interval

      missing = 0
      threshold_buckets.times do |i|
        bucket = now_bucket - ((i + 1) * interval * 60)
        ticks  = OptionsBuying::StateStore.minute_ticks(security_id, bucket)
        missing += 1 unless ticks.any?
      end

      missing >= threshold_buckets
    rescue StandardError
      false
    end

    # -------------------------------------------------------------------------
    # DhanHQ fetch
    # -------------------------------------------------------------------------

    def fetch_with_retry(instrument, interval, from_date, to_date)
      attempts = 0

      begin
        attempts += 1
        raw = instrument.intraday_ohlc(interval: interval.to_s, from_date: from_date, to_date: to_date)
        return raw if raw.present?

        nil
      rescue StandardError => e
        Rails.logger.warn(
          "[HistoricalBackfillService] Fetch attempt #{attempts}/#{MAX_RETRIES + 1} failed: #{e.message}"
        )
        if attempts <= MAX_RETRIES
          sleep 2
          retry
        end
        nil
      end
    end

    # -------------------------------------------------------------------------
    # Normalization
    # -------------------------------------------------------------------------

    # Normalise the raw DhanHQ response into a homogeneous array of candle hashes.
    # Delegates to CandleSeries#normalise_candles for DRY normalization.
    def normalize_raw(raw)
      scratch = CandleSeries.new(symbol: "_backfill_", interval: "1")
      scratch.normalise_candles(raw).first(MAX_CANDLES_PER_BACKFILL)
    end

    # -------------------------------------------------------------------------
    # Storage
    # -------------------------------------------------------------------------

    def store_candles(security_id, interval, candles)
      return { count: 0, min_bucket: nil, max_bucket: nil } if candles.blank?

      buckets = []

      candles.each do |candle|
        ts = parse_candle_timestamp(candle[:timestamp])
        next unless ts

        bucket = bucket_for(ts, interval)
        payloads = translate_to_tick_payloads(candle, bucket, interval)

        payloads.each do |payload|
          OptionsBuying::StateStore.append_minute_tick(security_id, bucket, payload)
        end

        buckets << bucket
      end

      { count: candles.size, min_bucket: buckets.min, max_bucket: buckets.max }
    end

    # Each historical candle becomes two synthetic ticks — open (start of bucket)
    # and close (1 second before bucket end). Volume is split equally.
    # This is enough for BreakoutEvaluator to reconstruct open/close/volume/oi.
    def translate_to_tick_payloads(candle, bucket, interval)
      vol = (candle[:volume].to_i / 2.0).ceil
      oi  = candle[:oi].to_i

      open_tick = {
        ts: bucket,
        ltp: candle[:open].to_f,
        oi: oi,
        vol: vol
      }

      close_tick = {
        ts: bucket + (interval * 60) - 1,
        ltp: candle[:close].to_f,
        oi: oi,
        vol: vol
      }

      [open_tick, close_tick]
    end

    def parse_candle_timestamp(ts)
      return ts if ts.is_a?(Time) || ts.is_a?(ActiveSupport::TimeWithZone)

      Time.zone.parse(ts.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def bucket_for(time, interval)
      t = time.to_i
      t - (t % (interval * 60))
    end

    # -------------------------------------------------------------------------
    # Rate limiting
    # -------------------------------------------------------------------------

    def rate_limit_wait!
      last_ts = redis.get(RATE_TS_KEY).to_i
      elapsed = Time.current.to_i - last_ts
      return unless elapsed < RATE_LIMIT_INTERVAL

      sleep_for = RATE_LIMIT_INTERVAL - elapsed
      Rails.logger.debug("[HistoricalBackfillService] Rate-limiting: sleeping #{sleep_for}s")
      sleep sleep_for
    end

    def update_rate_ts!
      redis.set(RATE_TS_KEY, Time.current.to_i, ex: 60)
    end

    # -------------------------------------------------------------------------
    # Circuit breaker
    # -------------------------------------------------------------------------

    def circuit_open?
      redis.exists?(CIRCUIT_OPEN_KEY)
    end

    def circuit_open_result
      Rails.logger.warn("[HistoricalBackfillService] Circuit breaker OPEN — skipping backfill")
      { success: false, candles_fetched: 0, min_bucket: nil, max_bucket: nil, error: "circuit_open" }
    end

    def record_failure!
      count = redis.incr(FAILURE_CTR_KEY)
      redis.expire(FAILURE_CTR_KEY, 300)

      return unless count >= CIRCUIT_BREAKER_THRESHOLD

      redis.set(CIRCUIT_OPEN_KEY, "1", ex: CIRCUIT_BREAKER_PAUSE)
      Rails.logger.error(
        "[HistoricalBackfillService] Circuit breaker TRIPPED after #{count} failures " \
        "(pausing #{CIRCUIT_BREAKER_PAUSE}s)"
      )
    end

    def reset_failures!
      redis.del(FAILURE_CTR_KEY)
      redis.del(CIRCUIT_OPEN_KEY)
    end

    # -------------------------------------------------------------------------
    # Redis
    # -------------------------------------------------------------------------

    def redis
      @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
    end
  end
end
