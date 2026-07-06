# frozen_string_literal: true

module Candles
  class PersistCandlesJob < ApplicationJob
    queue_as :background

    def perform(instrument_key:, exchange_segment:, security_id:, timeframe:, candles:, source: "live")
      return if candles.blank?

      now = Time.current
      rows = candles.map do |c|
        {
          instrument_key: instrument_key,
          exchange_segment: exchange_segment,
          security_id: security_id,
          timeframe: timeframe,
          ts: Time.iso8601(c["timestamp"]),
          open: c["open"],
          high: c["high"],
          low: c["low"],
          close: c["close"],
          volume: c["volume"],
          oi: c["oi"],
          source: source,
          created_at: now,
          updated_at: now
        }
      end

      Candles::Record.upsert_all(rows, unique_by: %i[instrument_key timeframe ts])
    end
  end
end
