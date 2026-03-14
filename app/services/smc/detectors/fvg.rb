# frozen_string_literal: true

module Smc
  module Detectors
    class Fvg
      DISPLACEMENT_THRESHOLD = 0.8
      # RVR > 1.5x rolling 20-period average (SMC spec: displacement = institutional)
      RVR_MIN = 1.5
      VOLUME_LOOKBACK = 20

      def initialize(series)
        @series = series
      end

      def gaps
        # Only check the last 30 candles for active FVGs
        lookback = [0, candles.size - 30].max

        (lookback...(candles.size - 2)).filter_map do |i|
          detect_fvg(i)
        end
      end

      def active_gaps
        gaps.reject { |g| mitigated?(g) }
      end

      def to_h
        {
          all_gaps: gaps,
          active: active_gaps
        }
      end

      private

      def detect_fvg(i)
        c1 = candles[i]
        c2 = candles[i + 1]
        c3 = candles[i + 2]

        return nil unless c1 && c2 && c3
        return nil unless displacement?(c2)

        if c1.high < c3.low
          { type: :bullish, from: c1.high, to: c3.low, index: i + 1, timestamp: c2.timestamp }
        elsif c1.low > c3.high
          { type: :bearish, from: c3.high, to: c1.low, index: i + 1, timestamp: c2.timestamp }
        end
      end

      def displacement?(candle)
        return false unless candle

        atr = @series.atr(20)
        body_size = (candle.close - candle.open).abs
        return false if atr && body_size <= (atr * DISPLACEMENT_THRESHOLD)
        return true unless atr # Not enough data for ATR: allow by body size only

        # Volume confirmation when available (RVR > 1.5x per SMC spec)
        rvr_ok = rvr_above_threshold?(candle)
        rvr_ok.nil? ? true : rvr_ok
      end

      # Returns true if volume > RVR_MIN * avg_volume_20, false if below, nil if no volume data
      def rvr_above_threshold?(candle)
        idx = candles.index(candle)
        return nil unless idx && idx >= VOLUME_LOOKBACK

        window = candles[(idx - VOLUME_LOOKBACK)...idx]
        return nil unless window.all? { |c| c.respond_to?(:volume) && c.volume.to_i.positive? }

        avg = window.sum(&:volume).to_f / VOLUME_LOOKBACK
        return nil if avg.zero?

        (candle.volume.to_f / avg) >= RVR_MIN
      end

      def mitigated?(gap)
        # Check if any subsequent candle high/low has entered the gap
        start_index = gap[:index] + 2
        return false if start_index >= candles.size

        candles[start_index..].any? do |c|
          if gap[:type] == :bullish
            c.low <= gap[:to] # Price dipped into the gap
          else
            c.high >= gap[:from] # Price rose into the gap
          end
        end
      end

      def candles
        @series&.candles || []
      end
    end
  end
end
