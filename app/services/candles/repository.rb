# frozen_string_literal: true

module Candles
  # Read API over durably-persisted candles. The 1m timeframe reads straight
  # from the table; every other timeframe is derived on read via OHLC rollup
  # over the 1m rows — no higher-timeframe rows are ever stored (see
  # docs/infra-strategy-setup/03_data_layer.md, D-03.2).
  class Repository
    BASE_TIMEFRAME = "1m"
    TIMEFRAME_PATTERN = /\A([1-9]\d*)m\z/

    class << self
      # @param instrument_key [String]
      # @param timeframe [String] e.g. "1m", "3m", "5m", "15m"
      # @param from [Time]
      # @param to [Time]
      # @param include_forming [Boolean] merge the forming bar from Live::CandleSeriesCache
      # @param instrument [Instrument, nil] required to resolve the forming bar
      # @return [CandleSeries] ordered by ts ascending
      def series(instrument_key:, from:, to:, timeframe: BASE_TIMEFRAME, include_forming: false, instrument: nil)
        rows = base_series(instrument_key: instrument_key, from: from, to: to)

        if include_forming && instrument
          forming = forming_row(instrument)
          if forming && forming[:ts] >= from && forming[:ts] <= to &&
             (rows.empty? || forming[:ts] > rows.last[:ts])
            rows << forming
          end
        end

        rows = rollup(rows, timeframe) unless timeframe.to_s == BASE_TIMEFRAME
        to_candle_series(instrument_key, timeframe, rows)
      end

      # Resample an in-memory Array<Candle> not backed by the `Record` table (e.g. a
      # backtester's own already-fetched historical candles) using the same bucketing
      # rules as the durable-data path.
      # @param candles [Array<Candle>] ascending by timestamp
      # @param symbol [String]
      # @param timeframe [String] e.g. "1m", "3m", "5m"
      # @return [CandleSeries]
      def rollup_candles(candles:, symbol:, timeframe:)
        rows = candles.map do |c|
          { ts: c.timestamp, open: c.open, high: c.high, low: c.low, close: c.close, volume: c.volume, oi: 0 }
        end
        rows = rollup(rows, timeframe) unless timeframe.to_s == BASE_TIMEFRAME
        to_candle_series(symbol, timeframe, rows)
      end

      private

      def base_series(instrument_key:, from:, to:)
        rows = Record
               .for_instrument(instrument_key)
               .for_timeframe(BASE_TIMEFRAME)
               .between(from, to)
               .order(:ts)
               .pluck(:ts, :open, :high, :low, :close, :volume, :oi)
               .map do |ts, o, h, l, c, v, oi|
          { ts: ts, open: o.to_f, high: h.to_f, low: l.to_f, close: c.to_f, volume: v.to_i, oi: oi.to_i }
        end

        # Fall back to Redis candle cache when Solid Queue worker hasn't
        # persisted today's candles yet (the WS-tick → Redis → DB pipeline
        # requires a separate jobs process).
        if rows.empty? && (instrument = find_instrument(instrument_key))
          cached = Live::CandleSeriesCache.fetch(instrument: instrument, interval: 1, backfill: false)
          if cached&.candles
            rows = cached.candles.reject { |c| c.timestamp.nil? || c.timestamp < from || c.timestamp > to }
                         .map do |c|
      { ts: c.timestamp, open: c.open.to_f, high: c.high.to_f,
        low: c.low.to_f, close: c.close.to_f, volume: c.volume.to_i, oi: 0 }
            end
          end
        end

        rows
      end

      def find_instrument(instrument_key)
        Instrument.find_by(symbol_name: instrument_key)
      rescue StandardError
        nil
      end

      # NOTE: `from` should be bucket-aligned for the requested timeframe.
      # `.between(from, to)` is inclusive over raw 1m rows, so an unaligned
      # `from` (e.g. "3m" starting at :16 instead of :15) yields a leading
      # bucket built from a partial set of 1m bars.
      # The most recent (still-forming) bar lives only in the Redis candle
      # cache, never in the durable table.
      def forming_row(instrument)
        cached = Live::CandleSeriesCache.fetch(instrument: instrument, interval: 1, backfill: false)
        last = cached&.candles&.last
        return nil unless last

        {
          ts: last.timestamp,
          open: last.open, high: last.high, low: last.low, close: last.close,
          volume: last.volume, oi: 0
        }
      rescue StandardError => e
        Rails.logger.warn("[Candles::Repository] forming_row failed for #{instrument.security_id}: #{e.message}")
        nil
      end

      def to_candle_series(instrument_key, timeframe, rows)
        series = CandleSeries.new(symbol: instrument_key, interval: minutes_for(timeframe).to_s)
        rows.each do |r|
          series.add_candle(
            Candle.new(
              timestamp: r[:ts], open: r[:open], high: r[:high],
              low: r[:low], close: r[:close], volume: r[:volume]
            )
          )
        end
        series
      end

      def rollup(base, timeframe)
        minutes = minutes_for(timeframe)
        return [] if base.empty?

        base
          .group_by { |c| bucket_start(c[:ts], minutes) }
          .sort_by { |bucket_ts, _| bucket_ts }
          .map do |bucket_ts, bucket_candles|
            {
              ts: bucket_ts,
              open: bucket_candles.first[:open],
              high: bucket_candles.map { |c| c[:high] }.max,
              low: bucket_candles.map { |c| c[:low] }.min,
              close: bucket_candles.last[:close],
              volume: bucket_candles.sum { |c| c[:volume] },
              oi: bucket_candles.last[:oi]
            }
          end
      end

      def minutes_for(timeframe)
        match = TIMEFRAME_PATTERN.match(timeframe.to_s)
        raise ArgumentError, "Unsupported timeframe: #{timeframe.inspect}" unless match

        match[1].to_i
      end

      def bucket_start(ts, minutes)
        local = ts.in_time_zone
        midnight = local.beginning_of_day
        minutes_since_midnight = ((local - midnight) / 60).to_i
        bucket_index = minutes_since_midnight / minutes
        midnight + (bucket_index * minutes).minutes
      end
    end
  end
end
