# frozen_string_literal: true

module Research
  # Backfills 1-min underlying candles into Candles::Record so
  # MarketDataFetcher's existing DB read covers more trading days.
  class UnderlyingBackfill
    CHUNK_DAYS = 75

    def self.call(symbol: "NIFTY", lookback_days: 90)
      instrument = Instrument.find_by(exchange: "nse", segment: "index", symbol_name: symbol)
      return existing_day_count(symbol) unless instrument

      existing = Candles::Record.where(instrument_key: symbol, timeframe: "1m")
                                .pluck(Arel.sql("DISTINCT ts::date")).to_set

      from = lookback_days.days.ago.to_date
      to = Time.zone.today

      (from..to).each_slice(CHUNK_DAYS) do |chunk|
        chunk_from = chunk.first
        chunk_to = chunk.last
        next if (chunk_from..chunk_to).all? { |d| existing.include?(d) || d.saturday? || d.sunday? }

        raw = instrument.intraday_ohlc(interval: "1", from_date: chunk_from.to_s, to_date: chunk_to.to_s)
        persist(instrument, symbol, raw, existing)
      rescue StandardError => e
        Rails.logger.warn("[Research::UnderlyingBackfill] chunk #{chunk_from}..#{chunk_to} failed: #{e.class} - #{e.message}")
      end

      existing_day_count(symbol)
    end

    def self.persist(instrument, symbol, raw, existing)
      return if raw.blank? || raw[:timestamp].blank?

      rows = raw[:timestamp].each_index.filter_map do |i|
        ts = Time.zone.at(raw[:timestamp][i])
        next if existing.include?(ts.to_date)

        {
          instrument_key: symbol, exchange_segment: instrument.exchange_segment,
          security_id: instrument.security_id, timeframe: "1m", ts: ts,
          open: raw[:open][i], high: raw[:high][i], low: raw[:low][i],
          close: raw[:close][i], volume: raw[:volume][i], source: "research_backfill",
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
