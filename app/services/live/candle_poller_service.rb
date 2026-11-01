# frozen_string_literal: true

module Live
  class CandlePollerService
    POLL_INTERVAL = 30

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

    # Polling only covers the last few minutes, so without this the strategies
    # start each session with no history and every indicator reports
    # insufficient data. to_date is explicit because intraday_ohlc defaults to
    # yesterday.
    def enqueue_warmup_backfill
      to_date = Time.current.strftime("%Y-%m-%d %H:%M:%S")
      IndexConfigLoader.load_indices.each do |idx|
        instrument = IndexInstrumentCache.instance.get_or_fetch(idx)
        Candles::BackfillJob.perform_later(security_id: instrument.security_id.to_s, to_date: to_date) if instrument
      end
    rescue StandardError => e
      Rails.logger.error("[CandlePollerService] warmup backfill enqueue failed: #{e.class} - #{e.message}")
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
