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
      now.between?(now.beginning_of_day + 9.hours + 15.minutes, now.beginning_of_day + 15.hours + 30.minutes)
    end

    def cache_candles(index_key, sid, segment, timeframe)
      candles = Market::CandleSeries.new(
        security_id: sid,
        segment: segment,
        timeframe: timeframe
      ).fetch(limit: LIMITS[timeframe])

      return if candles.blank?

      StateStore.cache_index_candles(index_key, timeframe, candles)
    rescue StandardError => e
      Rails.logger.warn("[CandlePrecomputeJob] #{index_key} #{timeframe}m failed: #{e.class} - #{e.message}")
    end
  end
end