# frozen_string_literal: true

module Candles
  # Gateway between the live candle-cache path and durable storage.
  #
  # Never writes to the DB directly — always hands off to a Solid Queue job so
  # callers on the WebSocket tick path (Live::CandleSeriesCache#append_tick)
  # never block on a DB write.
  class Persister
    INDEX_SEGMENT = "index"

    class << self
      # @param instrument [Instrument]
      # @param interval [Integer] candle interval in minutes
      # @param candles [Array<Hash>] string-keyed candle hashes (see class doc)
      # @param source ["live", "backfill"]
      def enqueue(instrument:, interval:, candles:, source: "live")
        return unless persistable?(instrument, interval)
        return if candles.blank?

        Candles::PersistCandlesJob.perform_later(
          instrument_key: instrument.symbol_name,
          exchange_segment: instrument.exchange_segment,
          security_id: instrument.security_id.to_s,
          timeframe: timeframe_for(interval),
          source: source,
          candles: serialize(candles)
        )
      end

      # @param instrument [Instrument, nil]
      # @param interval [Integer, String]
      # @return [Boolean]
      def persistable?(instrument, interval)
        instrument.present? && interval.to_i == 1 && instrument.segment == INDEX_SEGMENT
      end

      def timeframe_for(interval)
        "#{interval.to_i}m"
      end

      private

      def serialize(candles)
        candles.map do |c|
          {
            "timestamp" => normalize_ts(c["timestamp"]),
            "open" => c["open"].to_f,
            "high" => c["high"].to_f,
            "low" => c["low"].to_f,
            "close" => c["close"].to_f,
            "volume" => c["volume"].to_i,
            "oi" => c["oi"].to_i
          }
        end
      end

      def normalize_ts(raw)
        return raw.utc.iso8601(3) if raw.respond_to?(:utc)

        raw.to_s
      end
    end
  end
end
