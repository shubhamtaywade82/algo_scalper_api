# frozen_string_literal: true

module OptionsBuying
  # Pre-computes and caches index candles for all strategy timeframes.
  # Runs every minute during market hours via Solid Queue priority 5 (before strategy evaluation).
  class CandlePrecomputeJob < ApplicationJob
    queue_as :background

    TIMEFRAMES = %w[1 5 15 60 D].freeze

    def perform(*_args)
      return unless market_hours?

      IndexConfigLoader.load_indices.each do |idx|
        index_key = idx[:key].to_s.upcase
        sid = idx[:sid].to_s
        segment = idx[:segment].to_s

        TIMEFRAMES.each do |tf|
          cache_candles(index_key, sid, segment, tf)
        end
      rescue StandardError => e
        Rails.logger.error("[CandlePrecomputeJob] #{index_key} failed: #{e.class} - #{e.message}")
      end
    end

    private

    def market_hours?
      now = Time.current
      now >= now.beginning_of_day + 9.hours + 15.minutes && now <= now.beginning_of_day + 15.hours + 30.minutes
    end

    def days_for_timeframe(timeframe)
      case timeframe.to_s
      when '1' then 5
      when '5' then 10
      when '15' then 20
      when '60' then 30
      else 5
      end
    end

    def cache_candles(index_key, sid, segment, timeframe)
      instrument = Instrument.find_by(security_id: sid.to_i)
      return unless instrument

      raw_candles = if timeframe == 'D'
                      instrument.historical_ohlc
                    else
                      instrument.intraday_ohlc(
                        interval: timeframe,
                        days: days_for_timeframe(timeframe)
                      )
                    end
      return if raw_candles.blank?

      series = CandleSeries.new(symbol: sid, interval: timeframe)
      series.load_from_raw(raw_candles)

      StateStore.cache_index_candles(index_key, timeframe, series.to_hash)
    rescue StandardError => e
      Rails.logger.warn("[CandlePrecomputeJob] #{index_key} #{timeframe}m failed: #{e.class} - #{e.message}")
    end
  end
end
