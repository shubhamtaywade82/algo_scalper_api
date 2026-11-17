# frozen_string_literal: true

module Live
  class CandlePollerService
    POLL_INTERVAL = 30
    WARMUP_OVERLAP = 15.minutes
    BACKFILL_TIME_FORMAT = '%Y-%m-%d %H:%M:%S'

    def initialize
      @running = false
      @thread = nil
    end

    def start
      return if @running

      @running = true
      @thread = Thread.new { poll_loop }
      Rails.logger.info("[CandlePollerService] started (interval=#{POLL_INTERVAL}s)")
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
      Rails.logger.info("[CandlePollerService] stopped")
    end

    def running?
      @running
    end

    def healthy?
      @running && @thread&.alive?
    end

    private

    def poll_loop
      enqueue_warmup_backfill
      while @running
        poll_indices
        sleep POLL_INTERVAL
      end
    rescue StandardError => e
      Rails.logger.error("[CandlePollerService] poll loop crashed: #{e.class} - #{e.message}")
      @running = false
    end

    # Polling only covers the last few minutes, so a session that starts (or resumes) with a hole in
    # the stored bars leaves the strategies without history. to_date is explicit because
    # intraday_ohlc defaults to yesterday.
    #
    # Only the gap is fetched: re-fetching and re-upserting days of bars that are already stored made
    # every daemon start (even after the close) a ~4,500-row write plus three Dhan data-API calls.
    def enqueue_warmup_backfill
      to_date = Time.current.strftime(BACKFILL_TIME_FORMAT)
      IndexConfigLoader.load_indices.each do |idx|
        instrument = IndexInstrumentCache.instance.get_or_fetch(idx)
        next unless instrument

        job_args = { security_id: instrument.security_id.to_s, to_date: to_date }
        from_date = warmup_from_date(instrument)
        job_args[:from_date] = from_date if from_date
        Candles::BackfillJob.perform_later(**job_args)
      end
    rescue StandardError => e
      Rails.logger.error("[CandlePollerService] warmup backfill enqueue failed: #{e.class} - #{e.message}")
    end

    # nil means "no stored bars": the job then uses its own default lookback.
    def warmup_from_date(instrument)
      last_stored = Candles::Record.for_instrument(instrument.symbol_name).for_timeframe('1m').maximum(:ts)
      return nil unless last_stored

      # The overlap re-fetches the tail, whose last bar may have been stored while still forming.
      from = [last_stored - WARMUP_OVERLAP, Candles::BackfillJob::DEFAULT_LOOKBACK_DAYS.days.ago].max
      from.in_time_zone.strftime(BACKFILL_TIME_FORMAT)
    end

    def poll_indices
      IndexConfigLoader.load_indices.each do |idx|
        next unless @running

        instrument = IndexInstrumentCache.instance.get_or_fetch(idx)
        unless instrument
          Rails.logger.warn("[CandlePollerService] no instrument for #{idx[:key]}")
          next
        end

        result = CandleSeriesCache.poll_candle_closure(instrument: instrument, interval: 1)
        if result[:published].positive?
          Rails.logger.info("[CandlePollerService] published #{result[:published]} candle_closed events for #{instrument.symbol_name}")
        end
      rescue StandardError => e
        Rails.logger.warn("[CandlePollerService] poll error for #{idx[:key]}: #{e.class} - #{e.message}")
      end
    rescue StandardError => e
      Rails.logger.error("[CandlePollerService] poll_indices error: #{e.class} - #{e.message}")
    end
  end
end
