# frozen_string_literal: true

module Smc
  module Detectors
    class OrderBlocks
      DISPLACEMENT_THRESHOLD = 0.8
      RVR_MIN = 1.5
      VOLUME_LOOKBACK = 20

      def initialize(series)
        @series = series
      end

      # Latest unmitigated bullish order block
      def bullish
        active_blocks.reverse.find { |b| b[:bias] == :bullish }
      end

      # Latest unmitigated bearish order block
      def bearish
        active_blocks.reverse.find { |b| b[:bias] == :bearish }
      end

      def active_blocks
        @active_blocks ||= find_blocks.reject { |b| mitigated?(b) }
      end

      def find_blocks
        return @find_blocks if defined?(@find_blocks)

        @find_blocks = compute_blocks
      end

      def compute_blocks
        blocks = []
        # Need at least 4 candles: (0...(4-3)) => one index for a=0, b=1
        return [] if candles.size < 4

        # Scan the last 30 candles
        lookback = [0, candles.size - 30].max

        (lookback...(candles.size - 3)).each do |i|
          # We look for: Opposing candle -> Displacement candle -> Optional continuation
          a = candles[i]
          b = candles[i + 1]

          next unless a && b
          next unless displacement?(b, i + 1)

          if a.bearish? && b.bullish? && b.close > a.high
            blocks << { bias: :bullish, high: a.high, low: a.low, index: i, timestamp: a.timestamp }
          elsif a.bullish? && b.bearish? && b.close < a.low
            blocks << { bias: :bearish, high: a.high, low: a.low, index: i, timestamp: a.timestamp }
          end
        end

        blocks
      end

      def find_candle_by_index(index)
        candles[index] if index && candles[index]
      end

      def to_h
        {
          bullish: bullish,
          bearish: bearish,
          active: active_blocks
        }
      end

      private

      def displacement?(candle, candle_index = nil)
        return false unless candle

        atr = cached_atr
        body_size = (candle.close - candle.open).abs
        return false if atr && body_size <= (atr * DISPLACEMENT_THRESHOLD)
        return true unless atr

        rvr_ok = rvr_above_threshold?(candle, candle_index)
        rvr_ok.nil? || rvr_ok
      end

      def rvr_above_threshold?(candle, candle_index = nil)
        idx = candle_index || candles.index(candle)
        return nil unless idx && idx >= VOLUME_LOOKBACK # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

        window = candles[(idx - VOLUME_LOOKBACK)...idx]
        return nil unless window.all? { |c| c.respond_to?(:volume) && c.volume.to_i.positive? } # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

        avg = window.sum(&:volume).to_f / VOLUME_LOOKBACK
        return nil if avg.zero? # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

        (candle.volume.to_f / avg) >= RVR_MIN
      end

      def mitigated?(block)
        # Skip the displacement candle (index + 1); mitigation starts after the impulse.
        start_index = block[:index] + 2
        return false if start_index >= candles.size

        candles[start_index..].any? do |c|
          if block[:bias] == :bullish
            c.low <= block[:low]
          else
            c.high >= block[:high]
          end
        end
      end

      def candles
        @series&.candles || []
      end

      def cached_atr
        return @cached_atr if defined?(@cached_atr)

        @cached_atr = @series.atr(20)
      end
    end
  end
end
