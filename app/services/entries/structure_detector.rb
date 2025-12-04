# frozen_string_literal: true

module Entries
  # Detects market structure patterns (BOS, Order Blocks, FVG) without volume
  class StructureDetector
    class << self
      # Break of Structure (BOS) - price breaks previous swing high/low
      # @param bars [Array<Candle>] Array of candle objects
      # @param lookback_minutes [Integer] Minutes to look back for BOS
      # @return [Boolean]
      def bos?(bars, lookback_minutes: 10)
        return false if bars.nil? || bars.empty? || bars.size < 3

        lookback_count = [lookback_minutes, bars.size].min
        recent_bars = bars.last(lookback_count)
        return false if recent_bars.size < 3

        current = recent_bars.last
        return false unless current

        previous_bars = recent_bars[0..-2]
        return false if previous_bars.empty?

        previous_swing_high = previous_bars.map(&:high).max
        previous_swing_low = previous_bars.map(&:low).min

        return false unless previous_swing_high && previous_swing_low

        # Bullish BOS: price breaks above previous swing high
        bullish_bos = current.close > previous_swing_high

        # Bearish BOS: price breaks below previous swing low
        bearish_bos = current.close < previous_swing_low

        bullish_bos || bearish_bos
      end

      # Check if price is inside opposite Order Block
      # Order Block: last bullish/bearish candle before a strong move
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Boolean]
      def inside_opposite_ob?(bars)
        return false if bars.size < 3

        current = bars.last
        return false unless current

        # Look for recent Order Block (last 5 candles)
        recent = bars.last(5)
        return false if recent.size < 3

        # Find last strong move direction
        move_direction = detect_move_direction(recent)
        return false unless move_direction

        # Check if current price is inside opposite OB
        ob_range = find_order_block_range(recent, move_direction)
        return false unless ob_range

        case move_direction
        when :bullish
          # If recent move was bullish, check if we're in bearish OB
          current.close < ob_range[:high] && current.close > ob_range[:low]
        when :bearish
          # If recent move was bearish, check if we're in bullish OB
          current.close > ob_range[:low] && current.close < ob_range[:high]
        else
          false
        end
      end

      # Check if price is inside opposing Fair Value Gap (FVG)
      # FVG: gap between candle bodies (not wicks)
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Boolean]
      def inside_fvg?(bars)
        return false if bars.size < 3

        current = bars.last
        recent = bars.last(5)
        return false if recent.size < 3

        # Find FVGs in recent candles
        fvgs = find_fair_value_gaps(recent)
        return false if fvgs.empty?

        # Check if current price is inside any opposing FVG
        fvgs.any? do |fvg|
          price_inside_fvg?(current, fvg)
        end
      end

      private

      def detect_move_direction(bars)
        return nil if bars.size < 3

        first_close = bars.first.close
        last_close = bars.last.close
        move_pct = ((last_close - first_close) / first_close * 100).abs

        return nil if move_pct < 0.1 # Less than 0.1% move

        last_close > first_close ? :bullish : :bearish
      end

      def find_order_block_range(bars, direction)
        return nil if bars.size < 2

        case direction
        when :bullish
          # Bullish OB: last bearish candle before bullish move
          (bars.size - 2).downto(0) do |i|
            candle = bars[i]
            next unless candle.bearish?

            return { low: candle.low, high: candle.high }
          end
        when :bearish
          # Bearish OB: last bullish candle before bearish move
          (bars.size - 2).downto(0) do |i|
            candle = bars[i]
            next unless candle.bullish?

            return { low: candle.low, high: candle.high }
          end
        end

        nil
      end

      def find_fair_value_gaps(bars)
        gaps = []
        return gaps if bars.size < 3

        (0..bars.size - 3).each do |i|
          candle1 = bars[i]
          candle2 = bars[i + 1]
          candle3 = bars[i + 2]

          # Bullish FVG: gap between candle1 high and candle3 low
          if candle3.low > candle1.high
            gaps << {
              type: :bullish,
              low: candle1.high,
              high: candle3.low
            }
          end

          # Bearish FVG: gap between candle1 low and candle3 high
          if candle3.high < candle1.low
            gaps << {
              type: :bearish,
              low: candle3.high,
              high: candle1.low
            }
          end
        end

        gaps
      end

      def price_inside_fvg?(candle, fvg)
        price = candle.close
        price >= fvg[:low] && price <= fvg[:high]
      end
    end
  end
end
