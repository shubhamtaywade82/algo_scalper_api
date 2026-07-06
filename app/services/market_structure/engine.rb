# frozen_string_literal: true

module AlgoScalper
  module MarketStructure
    class Engine
      attr_reader :config, :swings, :levels

      def initialize(config = {})
        @config = {
          left_bars: 5,
          right_bars: 5,
          min_swing_size: 15, # points for NIFTY
          structure_lookback: 20
        }.merge(config)

        @swings = { highs: [], lows: [] }
        @levels = { support: [], resistance: [] }
        @last_price = 0.0
      end

      def process(candle)
        @last_price = candle[:close] || candle[:c]

        detect_swings(candle)
        update_levels
        classify_structure
      end

      def bullish_structure?
        @structure == :bullish
      end

      def bearish_structure?
        @structure == :bearish
      end

      def range_structure?
        @structure == :range
      end

      def structure_score
        @structure_score || 0
      end

      def swing_highs
        @swings[:highs].last(5)
      end

      def swing_lows
        @swings[:lows].last(5)
      end

      def last_swing_high
        @swings[:highs].last
      end

      def last_swing_low
        @swings[:lows].last
      end

      def distance_to_resistance
        return nil if @levels[:resistance].empty?

        nearest = @levels[:resistance].min_by { |r| (r - @last_price).abs }
        ((nearest - @last_price) / @last_price * 100).round(2)
      end

      def distance_to_support
        return nil if @levels[:support].empty?

        nearest = @levels[:support].min_by { |s| (@last_price - s).abs }
        ((@last_price - nearest) / @last_price * 100).round(2)
      end

      def break_of_structure?
        @bos == true
      end

      def change_of_character?
        @choch == true
      end

      def liquidity_sweep?
        @liquidity_sweep == true
      end

      private

      def detect_swings(candle)
        high = candle[:high] || candle[:h]
        low = candle[:low] || candle[:l]
        time = candle[:time] || candle[:timestamp]

        # Check for swing high
        if swing_high?(high, time)
          @swings[:highs] << { price: high, time: time, index: @candles.size }
        end

        # Check for swing low
        if swing_low?(low, time)
          @swings[:lows] << { price: low, time: time, index: @candles.size }
        end

        # Keep only recent swings
        @swings[:highs] = @swings[:highs].last(@config[:structure_lookback])
        @swings[:lows] = @swings[:lows].last(@config[:structure_lookback])
      end

      def swing_high?(price, time)
        return false unless @candles.size >= @config[:left_bars] + @config[:right_bars] + 1

        center_idx = @candles.size - @config[:right_bars] - 1
        center_candle = @candles[center_idx]

        return false unless center_candle
        return false unless (center_candle[:high] || center_candle[:h]) == price

        # Check left side
        left_start = center_idx - @config[:left_bars]
        left_candles = @candles[left_start...center_idx]
        return false if left_candles.any? { |c| (c[:high] || c[:h]) >= price }

        # Check right side
        right_candles = @candles[center_idx + 1..center_idx + @config[:right_bars]]
        return false if right_candles.any? { |c| (c[:high] || c[:h]) > price }

        true
      end

      def swing_low?(price, time)
        return false unless @candles.size >= @config[:left_bars] + @config[:right_bars] + 1

        center_idx = @candles.size - @config[:right_bars] - 1
        center_candle = @candles[center_idx]

        return false unless center_candle
        return false unless (center_candle[:low] || center_candle[:l]) == price

        left_start = center_idx - @config[:left_bars]
        left_candles = @candles[left_start...center_idx]
        return false if left_candles.any? { |c| (c[:low] || c[:l]) <= price }

        right_candles = @candles[center_idx + 1..center_idx + @config[:right_bars]]
        return false if right_candles.any? { |c| (c[:low] || c[:l]) < price }

        true
      end

      def update_levels
        highs = @swings[:highs].map { |s| s[:price] }
        lows = @swings[:lows].map { |s| s[:price] }

        @levels[:resistance] = highs.select { |h| h > @last_price }.sort
        @levels[:support] = lows.select { |l| l < @last_price }.sort.reverse
      end

      def classify_structure
        highs = @swings[:highs].map { |s| s[:price] }
        lows = @swings[:lows].map { |s| s[:price] }

        return :unknown if highs.size < 2 || lows.size < 2

        # Check for higher highs / higher lows
        hh = highs[-1] > highs[-2]
        hl = lows[-1] > lows[-2]
        lh = highs[-1] < highs[-2]
        ll = lows[-1] < lows[-2]

        @bos = false
        @choch = false
        @liquidity_sweep = false

        if hh && hl
          @structure = :bullish
          @structure_score = calculate_bullish_score(highs, lows)
          @bos = check_bos(:bullish, highs, lows)
        elsif lh && ll
          @structure = :bearish
          @structure_score = calculate_bearish_score(highs, lows)
          @bos = check_bos(:bearish, highs, lows)
        else
          @structure = :range
          @structure_score = 50
        end

        @choch = check_choch
        @liquidity_sweep = check_liquidity_sweep
      end

      def calculate_bullish_score(highs, lows)
        score = 50
        score += 10 if highs[-1] > highs[-2] # HH
        score += 15 if lows[-1] > lows[-2]  # HL
        score += 10 if highs[-1] > highs[-3] if highs.size >= 3
        score += 15 if lows[-1] > lows[-3] if lows.size >= 3
        [score, 100].min
      end

      def calculate_bearish_score(highs, lows)
        score = 50
        score += 10 if highs[-1] < highs[-2] # LH
        score += 15 if lows[-1] < lows[-2]  # LL
        score += 10 if highs[-1] < highs[-3] if highs.size >= 3
        score += 15 if lows[-1] < lows[-3] if lows.size >= 3
        [score, 100].min
      end

      def check_bos(direction, highs, lows)
        return false unless highs.size >= 2 && lows.size >= 2

        if direction == :bullish
          # Price breaks above recent swing high
          @last_price > highs[-2]
        else
          # Price breaks below recent swing low
          @last_price < lows[-2]
        end
      end

      def check_choch
        # Change of character - structure breaks opposite direction
        return false if @structure == :range

        if @structure == :bullish
          # Was bullish, now making lower low
          @swings[:lows].size >= 2 && @swings[:lows][-1][:price] < @swings[:lows][-2][:price]
        else
          # Was bearish, now making higher high
          @swings[:highs].size >= 2 && @swings[:highs][-1][:price] > @swings[:highs][-2][:price]
        end
      end

      def check_liquidity_sweep
        # Price sweeps a level then reverses
        return false unless @last_price > 0

        # Check if we swept a swing high and reversed down
        @swings[:highs].any? do |h|
          @last_price < h[:price] && h[:price] < @last_price * 1.002
        end || @swings[:lows].any? do |l|
          @last_price > l[:price] && l[:price] > @last_price * 0.998
        end
      end

      # Candle storage
      def add_candle(candle)
        @candles ||= []
        @candles << candle
        @candles.shift if @candles.size > @config[:structure_lookback] * 2
      end
    end
  end
end