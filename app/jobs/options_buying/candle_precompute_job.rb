# frozen_string_literal: true

module OptionsBuying
  # Pre-computes and caches index candles for all strategy timeframes.
  # Runs every minute during market hours via Solid Queue priority 5 (before strategy evaluation).
  class CandlePrecomputeJob < ApplicationJob
    queue_as :background

    TIMEFRAMES = %w[1 5 15 60 D].freeze
    LIMITS = {
      '1' => 500,
      '5' => 300,
      '15' => 200,
      '60' => 100,
      'D' => 100
    }.freeze

    def perform(*_args)
      return unless market_hours?

      IndexConfigLoader.load_indices.each do |idx|
        index_key = idx[:key].to_s.upcase
        sid = idx[:sid].to_i

        TIMEFRAMES.each do |tf|
          cache_candles(index_key, sid, tf)
        end
      rescue StandardError => e
        Rails.logger.error("[CandlePrecomputeJob] #{index_key} failed: #{e.class} - #{e.message}")
      end
    end

    private

    def market_hours?
      now = Time.current
      now.between?(now.beginning_of_day + 9.hours + 15.minutes, now.beginning_of_day + 15.hours + 30.minutes)
    end

    def cache_candles(index_key, sid, timeframe)
      instrument = Instrument.find_by(security_id: sid)
      return unless instrument

      raw = timeframe == 'D' ? instrument.historical_ohlc : instrument.intraday_ohlc(interval: timeframe, days: 10)
      return if raw.blank?

      series = CandleSeries.new(symbol: index_key, interval: timeframe)
      series.load_from_raw(raw)
      candles = series.to_hash
      return if candles.blank?

      candles = candles.transform_values { |arr| arr.last(LIMITS[timeframe]) }
      StateStore.cache_index_candles(index_key, timeframe, candles)
    rescue StandardError => e
      Rails.logger.warn("[CandlePrecomputeJob] #{index_key} #{timeframe}m failed: #{e.class} - #{e.message}")
    end
  end
end