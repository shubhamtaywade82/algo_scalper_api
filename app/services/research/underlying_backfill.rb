# frozen_string_literal: true

module Research
  # Backfills 1-min underlying candles into Candles::Record so
  # MarketDataFetcher's existing DB read covers more trading days.
  class UnderlyingBackfill
    CHUNK_DAYS = 75

    def self.call(symbol: "NIFTY", lookback_days: 365)
      instrument = Instrument.segment_index.find_by(symbol_name: symbol)
      return existing_day_count(symbol) unless instrument

      existing = Candles::Record.where(instrument_key: symbol, timeframe: "1m")
                                .pluck(Arel.sql("DISTINCT ts::date")).to_set

      from = lookback_days.days.ago.to_date
      to = Time.zone.today

      (from..to).each_slice(CHUNK_DAYS) do |chunk|
        chunk_from = chunk.first
        chunk_to = chunk.last
        next if (chunk_from..chunk_to).all? { |d| existing.include?(d) || d.saturday? || d.sunday? }

        # Adjust dates to weekdays to satisfy DhanHQ API constraints
        chunk_from_adjusted = chunk_from
        chunk_from_adjusted += 1.day while chunk_from_adjusted.saturday? || chunk_from_adjusted.sunday?

        chunk_to_adjusted = chunk_to
        chunk_to_adjusted -= 1.day while chunk_to_adjusted.saturday? || chunk_to_adjusted.sunday?

        next if chunk_from_adjusted > chunk_to_adjusted

        raw = instrument.intraday_ohlc(interval: "1", from_date: chunk_from_adjusted.to_s, to_date: chunk_to_adjusted.to_s)
        persist(instrument, symbol, raw, existing)
      rescue StandardError => e
        Rails.logger.warn("[Research::UnderlyingBackfill] chunk #{chunk_from}..#{chunk_to} failed: #{e.class} - #{e.message}")
      end

      existing_day_count(symbol)
    end

    def self.persist(instrument, symbol, raw, existing)
      return if raw.blank?

      raw = raw.deep_stringify_keys if raw.respond_to?(:deep_stringify_keys)
      candles = CandleSeries.new(symbol: symbol, interval: "1").normalise_candles(raw)
      return if candles.blank?

      rows = candles.filter_map do |c|
        ts = c[:timestamp]
        next if existing.include?(ts.to_date)

        {
          instrument_key: symbol, exchange_segment: instrument.exchange_segment,
          security_id: instrument.security_id, timeframe: "1m", ts: ts,
          open: c[:open], high: c[:high], low: c[:low],
          close: c[:close], volume: c[:volume], source: "research_backfill",
          created_at: Time.current, updated_at: Time.current
        }
      end
      Candles::Record.insert_all(rows, unique_by: %i[instrument_key timeframe ts]) if rows.any?
    end

    def self.existing_day_count(symbol)
      Candles::Record.where(instrument_key: symbol, timeframe: "1m")
                     .pluck(Arel.sql("DISTINCT ts::date")).size
    end
  end
end
