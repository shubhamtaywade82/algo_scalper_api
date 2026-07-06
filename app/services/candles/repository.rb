# frozen_string_literal: true

module Candles
  class Repository
    BASE_TIMEFRAME = "1m"
    TIMEFRAME_PATTERN = /\A(\d+)m\z/

    class << self
      def series(instrument_key:, from:, to:, timeframe: BASE_TIMEFRAME)
        if timeframe.to_s == BASE_TIMEFRAME
          base_series(instrument_key: instrument_key, from: from, to: to)
        else
          derive(instrument_key: instrument_key, timeframe: timeframe, from: from, to: to)
        end
      end

      private

      def base_series(instrument_key:, from:, to:)
        Record
          .for_instrument(instrument_key)
          .for_timeframe(BASE_TIMEFRAME)
          .between(from, to)
          .order(:ts)
          .pluck(:ts, :open, :high, :low, :close, :volume, :oi)
          .map do |ts, o, h, l, c, v, oi|
            { ts: ts, open: o.to_f, high: h.to_f, low: l.to_f, close: c.to_f, volume: v.to_i, oi: oi.to_i }
          end
      end

      def derive(instrument_key:, timeframe:, from:, to:)
        minutes = minutes_for(timeframe)
        base = base_series(instrument_key: instrument_key, from: from, to: to)
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
        epoch = ts.to_i
        Time.zone.at(epoch - (epoch % (minutes * 60)))
      end
    end
  end
end
