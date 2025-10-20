# frozen_string_literal: true

require "singleton"

module Live
  class OhlcPrefetcherService
    include Singleton

    LOOP_INTERVAL_SECONDS = 60
    STAGGER_SECONDS = 0.5
    DEFAULT_INTERVAL = "5"
    LOOKBACK_DAYS = 2

    def initialize
      @mutex = Mutex.new
      @running = false
      @thread = nil
    end

    def start!
      return if @running

      @mutex.synchronize do
        return if @running
        @running = true
        @thread = Thread.new { run_loop }
        @thread.name = "ohlc-prefetcher"
      end
    end

    def stop!
      @mutex.synchronize do
        @running = false
        thread = @thread
        @thread = nil

        return unless thread
        return unless thread.alive?

        begin
          thread.wakeup
        rescue ThreadError
          # thread might not be sleeping; ignore
        end
      end
    end

    def running?
      @running
    end

    private

    def run_loop
      while running?
        fetch_all_watchlist
        sleep LOOP_INTERVAL_SECONDS
      end
    rescue StandardError => e
      Rails.logger.error("OhlcPrefetcherService crashed: #{e.class} - #{e.message}")
      @running = false
    end

    def fetch_all_watchlist
      return unless defined?(::WatchlistItem)

      WatchlistItem.active.find_in_batches(batch_size: 100) do |batch|
        batch.each do |wl|
          fetch_one(wl)
          sleep STAGGER_SECONDS
        end
      end
    end

    def fetch_one(wl)
      instrument = wl.watchable
      instrument ||= ::Instrument.find_by_sid_and_segment(
        security_id: wl.security_id,
        segment_code: wl.segment
      )
      unless instrument
        Rails.logger.debug("[OHLC prefetch] Instrument not found for #{wl.segment}:#{wl.security_id}")
        return
      end

      data = instrument.intraday_ohlc(interval: DEFAULT_INTERVAL, days: LOOKBACK_DAYS)

      count = 0
      first_time = nil
      last_time = nil
      last_close = nil

      if data.is_a?(Hash)
        ts = data[:timestamp] || data["timestamp"] || data[:time] || data["time"]
        if ts.is_a?(Array)
          count = ts.length
          first_time = ts.first ? Time.at(ts.first.to_f) : nil
          last_time  = ts.last  ? Time.at(ts.last.to_f)  : nil
          closes = data[:close] || data["close"]
          last_close = closes.last if closes.is_a?(Array) && closes.any?
        else
          # fall back to lengths of OHLC arrays if present
          arrays = %i[open high low close volume].map { |k| data[k] || data[k.to_s] }.compact.select { |v| v.is_a?(Array) }
          count = arrays.map(&:length).max || 0
        end
      elsif data.is_a?(Array)
        count = data.size
        if (bar = data.last).is_a?(Hash)
          tsv = bar[:time] || bar["time"]
          last_time = (Time.zone.parse(tsv.to_s) rescue nil) if tsv
          last_close = bar[:close] || bar["close"]
        end
      end

      Rails.logger.info("[OHLC prefetch] #{instrument.exchange_segment}:#{instrument.security_id} fetched=#{count} first=#{first_time} last=#{last_time} last_close=#{last_close}")
    rescue StandardError => e
      Rails.logger.warn("[OHLC prefetch] Failed for #{wl.segment}:#{wl.security_id} - #{e.class}: #{e.message}")
    end
  end
end
