# frozen_string_literal: true

module Candles
  # On-demand / scheduled seed and gap-fill of persisted 1m index candles.
  # Reuses the same DhanHQ fetch + normalization primitives as
  # Backtest::ApiLoader and Live::HistoricalBackfillService, but writes to the
  # durable candles table via Candles::Persister instead of the Redis-only
  # strike-tick pipeline those services target.
  class BackfillJob < ApplicationJob
    queue_as :background

    DEFAULT_LOOKBACK_DAYS = 5
    INDEX_SEGMENT = "index"

    def perform(security_id:, from_date: nil, to_date: nil, days: DEFAULT_LOOKBACK_DAYS)
      instrument = Instrument.find_by(security_id: security_id.to_s, segment: INDEX_SEGMENT)
      return unless instrument

      raw = instrument.intraday_ohlc(interval: "1", from_date: from_date, to_date: to_date, days: days)
      candles = CandleSeries.new(symbol: instrument.symbol_name, interval: "1").normalise_candles(raw)
      return if candles.blank?

      Candles::Persister.enqueue(
        instrument: instrument,
        interval: 1,
        candles: stringify(candles),
        source: "backfill"
      )
    end

    private

    def stringify(candles)
      candles.map do |c|
        {
          "timestamp" => c[:timestamp],
          "open" => c[:open],
          "high" => c[:high],
          "low" => c[:low],
          "close" => c[:close],
          "volume" => c[:volume],
          "oi" => c[:oi].to_i
        }
      end
    end
  end
end
