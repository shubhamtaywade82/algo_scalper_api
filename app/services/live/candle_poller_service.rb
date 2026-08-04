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
      while @running
        poll_indices
        sleep POLL_INTERVAL
      end
    rescue StandardError => e
      Rails.logger.error("[CandlePollerService] poll loop crashed: #{e.class} - #{e.message}")
      @running = false
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
