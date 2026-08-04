# frozen_string_literal: true

module Market
  # MarketRegimeResolver - Higher timeframe market regime detection using ONLY price structure.
  #
  # This service classifies the market regime as :bullish, :bearish, or :neutral
  # based purely on OHLC price action from 15-minute candles.
  #
  # CONSTRAINTS:
  # - NO indicators (RSI, MACD, ADX, ATR)
  # - NO volume
  # - NO SMC patterns
  # - NO AVRZ calculations
  # - NO AI/ML heuristics
  # - ONLY deterministic price structure analysis
  #
  # PURPOSE:
  # Acts as a HARD DIRECTION GATE to prevent trades against the prevailing regime:
  # - :bearish → Block all BUY CE trades
  # - :bullish → Block all BUY PE trades
  # - :neutral → No directional constraint
  #
  # rubocop:disable Metrics/ClassLength
  class MarketRegimeResolver < ApplicationService
    # Minimum candles required for analysis
    MIN_CANDLES = 20
    MAX_CANDLES = 30

    # Swing detection lookback (candles on each side to confirm swing)
    SWING_LOOKBACK = 3

    # Gap behavior observation window (candles)
    GAP_OBSERVATION_WINDOW = 4

    # Minimum swings required for trend confirmation
    MIN_SWING_SEQUENCE = 2

    def initialize(candles_15m:)
      @candles = normalize_candles(candles_15m)
    end

    def call
      return :neutral if @candles.size < MIN_CANDLES

      # Limit to most recent MAX_CANDLES
      @candles = @candles.last(MAX_CANDLES)

      # Detect structure
      swing_highs = detect_swing_highs
      swing_lows = detect_swing_lows

      # Check bearish conditions first (safety bias)
      return :bearish if bearish_regime?(swing_highs, swing_lows)

      # Check bullish conditions
      return :bullish if bullish_regime?(swing_highs, swing_lows)

      # Default to neutral if no clear regime
      :neutral
    end

    # Class-level convenience method
    def self.resolve(candles_15m:)
      call(candles_15m: candles_15m)
    end

    private

    # -------------------------------------------------------------------------
    # BEARISH REGIME DETECTION
    # -------------------------------------------------------------------------
    # Returns true if ANY of these conditions are met:
    # 1. Latest close < last confirmed swing low
    # 2. Sequence of lower highs AND lower lows (minimum 2)
    # 3. Gap down AND price fails to reclaim gap midpoint within 4 candles
    # 4. Price below previous day value midpoint and rejecting upward
    # -------------------------------------------------------------------------
    def bearish_regime?(swing_highs, swing_lows)
      # Condition 1: Latest close broke below last swing low
      return true if close_below_swing_low?(swing_lows)

      # Condition 2: Lower highs AND lower lows sequence
      return true if lower_highs_lower_lows?(swing_highs, swing_lows)

      # Condition 3: Gap down with failure to reclaim
      return true if gap_down_failed_reclaim?

      # Condition 4: Below value midpoint and rejecting
      return true if below_value_midpoint_rejecting?

      false
    end

    # -------------------------------------------------------------------------
    # BULLISH REGIME DETECTION
    # -------------------------------------------------------------------------
    # Returns true if ANY of these conditions are met:
    # 1. Latest close > last confirmed swing high
    # 2. Sequence of higher highs AND higher lows (minimum 2)
    # 3. Gap up AND price holds above gap midpoint for 4 candles
    # 4. Price above previous day value midpoint and holding
    # -------------------------------------------------------------------------
    def bullish_regime?(swing_highs, swing_lows)
      # Condition 1: Latest close broke above last swing high
      return true if close_above_swing_high?(swing_highs)

      # Condition 2: Higher highs AND higher lows sequence
      return true if higher_highs_higher_lows?(swing_highs, swing_lows)

      # Condition 3: Gap up with successful hold
      return true if gap_up_held?

      # Condition 4: Above value midpoint and holding
      return true if above_value_midpoint_holding?

      false
    end

    # -------------------------------------------------------------------------
    # SWING DETECTION
    # -------------------------------------------------------------------------

    # Detect swing highs: a candle with higher high than SWING_LOOKBACK candles on each side
    # Returns array of { index:, price: } hashes
    def detect_swing_highs
      swings = []
      return swings if @candles.size < ((SWING_LOOKBACK * 2) + 1)

      (SWING_LOOKBACK...(@candles.size - SWING_LOOKBACK)).each do |i|
        candidate_high = @candles[i][:high]

        # Check left side
        left_valid = (1..SWING_LOOKBACK).all? { |j| @candles[i - j][:high] < candidate_high }

        # Check right side
        right_valid = (1..SWING_LOOKBACK).all? { |j| @candles[i + j][:high] < candidate_high }

        swings << { index: i, price: candidate_high } if left_valid && right_valid
      end

      swings
    end

    # Detect swing lows: a candle with lower low than SWING_LOOKBACK candles on each side
    # Returns array of { index:, price: } hashes
    def detect_swing_lows
      swings = []
      return swings if @candles.size < ((SWING_LOOKBACK * 2) + 1)

      (SWING_LOOKBACK...(@candles.size - SWING_LOOKBACK)).each do |i|
        candidate_low = @candles[i][:low]

        # Check left side
        left_valid = (1..SWING_LOOKBACK).all? { |j| @candles[i - j][:low] > candidate_low }

        # Check right side
        right_valid = (1..SWING_LOOKBACK).all? { |j| @candles[i + j][:low] > candidate_low }

        swings << { index: i, price: candidate_low } if left_valid && right_valid
      end

      swings
    end

    # -------------------------------------------------------------------------
    # BEARISH CONDITION HELPERS
    # -------------------------------------------------------------------------

    # Condition 1: Latest close is below the last confirmed swing low
    def close_below_swing_low?(swing_lows)
      return false if swing_lows.empty?

      last_swing_low = swing_lows.last[:price]
      latest_close = @candles.last[:close]

      latest_close < last_swing_low
    end

    # Condition 2: Sequence of at least MIN_SWING_SEQUENCE lower highs AND lower lows
    def lower_highs_lower_lows?(swing_highs, swing_lows)
      return false if swing_highs.size < MIN_SWING_SEQUENCE || swing_lows.size < MIN_SWING_SEQUENCE

      # Check for lower highs in the last MIN_SWING_SEQUENCE+1 swing highs
      recent_highs = swing_highs.last(MIN_SWING_SEQUENCE + 1)
      lower_highs = all_descending?(recent_highs.pluck(:price))

      # Check for lower lows in the last MIN_SWING_SEQUENCE+1 swing lows
      recent_lows = swing_lows.last(MIN_SWING_SEQUENCE + 1)
      lower_lows = all_descending?(recent_lows.pluck(:price))

      lower_highs && lower_lows
    end

    # Condition 3: Gap down and failed to reclaim gap midpoint within observation window
    def gap_down_failed_reclaim?
      gap = detect_gap
      return false unless gap && gap[:direction] == :down

      gap_midpoint = gap[:midpoint]
      gap_candle_index = gap[:index]

      # Check if any candle in the observation window closed above the gap midpoint
      observation_end = [gap_candle_index + GAP_OBSERVATION_WINDOW, @candles.size - 1].min

      (gap_candle_index..observation_end).none? do |i|
        @candles[i][:close] > gap_midpoint
      end
    end

    # Condition 4: Price below previous session value midpoint and rejecting upward
    def below_value_midpoint_rejecting?
      value_midpoint = calculate_value_midpoint
      return false unless value_midpoint

      latest = @candles.last
      prior = @candles[-2]

      # Price is below midpoint
      below_midpoint = latest[:close] < value_midpoint

      # Rejecting upward: prior candle tried to go higher but got rejected (upper wick)
      # Upper wick > body and close below midpoint
      body = (latest[:close] - latest[:open]).abs
      upper_wick = latest[:high] - [latest[:open], latest[:close]].max

      rejection = upper_wick > body && latest[:close] < prior[:close]

      below_midpoint && rejection
    end

    # -------------------------------------------------------------------------
    # BULLISH CONDITION HELPERS
    # -------------------------------------------------------------------------

    # Condition 1: Latest close is above the last confirmed swing high
    def close_above_swing_high?(swing_highs)
      return false if swing_highs.empty?

      last_swing_high = swing_highs.last[:price]
      latest_close = @candles.last[:close]

      latest_close > last_swing_high
    end

    # Condition 2: Sequence of at least MIN_SWING_SEQUENCE higher highs AND higher lows
    def higher_highs_higher_lows?(swing_highs, swing_lows)
      return false if swing_highs.size < MIN_SWING_SEQUENCE || swing_lows.size < MIN_SWING_SEQUENCE

      # Check for higher highs in the last MIN_SWING_SEQUENCE+1 swing highs
      recent_highs = swing_highs.last(MIN_SWING_SEQUENCE + 1)
      higher_highs = all_ascending?(recent_highs.pluck(:price))

      # Check for higher lows in the last MIN_SWING_SEQUENCE+1 swing lows
      recent_lows = swing_lows.last(MIN_SWING_SEQUENCE + 1)
      higher_lows = all_ascending?(recent_lows.pluck(:price))

      higher_highs && higher_lows
    end

    # Condition 3: Gap up and held above gap midpoint for observation window
    def gap_up_held?
      gap = detect_gap
      return false unless gap && gap[:direction] == :up

      gap_midpoint = gap[:midpoint]
      gap_candle_index = gap[:index]

      # Check if ALL candles in the observation window stayed above the gap midpoint
      observation_end = [gap_candle_index + GAP_OBSERVATION_WINDOW, @candles.size - 1].min

      (gap_candle_index..observation_end).all? do |i|
        @candles[i][:close] > gap_midpoint
      end
    end

    # Condition 4: Price above previous session value midpoint and holding
    def above_value_midpoint_holding?
      value_midpoint = calculate_value_midpoint
      return false unless value_midpoint

      latest = @candles.last
      prior = @candles[-2]

      # Price is above midpoint
      above_midpoint = latest[:close] > value_midpoint

      # Holding: close is higher than or equal to prior close (not losing ground)
      holding = latest[:close] >= prior[:close]

      # Also check that lows are being respected (lower wick support)
      body = (latest[:close] - latest[:open]).abs
      lower_wick = [latest[:open], latest[:close]].min - latest[:low]

      # Support holding: lower wick shows buying interest
      support = lower_wick > body * 0.5 || holding

      above_midpoint && support
    end

    # -------------------------------------------------------------------------
    # GAP DETECTION
    # -------------------------------------------------------------------------

    # Detect the most recent significant gap
    # A gap occurs when current candle's low > prior candle's high (gap up)
    # or current candle's high < prior candle's low (gap down)
    # Returns { direction:, midpoint:, index: } or nil
    # rubocop:disable Metrics/AbcSize
    def detect_gap
      # Only look for gaps in the recent portion of candles
      search_start = [0, @candles.size - 10].max

      ((search_start + 1)...@candles.size).reverse_each do |i|
        current = @candles[i]
        prior = @candles[i - 1]

        # Gap up: current low > prior high
        if current[:low] > prior[:high]
          gap_size = current[:low] - prior[:high]
          avg_range = calculate_average_range
          # Only count significant gaps (> 20% of average range)
          if gap_size > avg_range * 0.2
            midpoint = prior[:high] + (gap_size / 2.0)
            return { direction: :up, midpoint: midpoint, index: i }
          end
        end

        # Gap down: current high < prior low
        next unless current[:high] < prior[:low]

        gap_size = prior[:low] - current[:high]
        avg_range = calculate_average_range
        # Only count significant gaps (> 20% of average range)
        if gap_size > avg_range * 0.2
          midpoint = current[:high] + (gap_size / 2.0)
          return { direction: :down, midpoint: midpoint, index: i }
        end
      end

      nil
    end
    # rubocop:enable Metrics/AbcSize

    # -------------------------------------------------------------------------
    # VALUE AREA / MIDPOINT CALCULATION
    # -------------------------------------------------------------------------

    # Calculate the value midpoint from the first half of candles (representing prior session)
    # Value midpoint = (highest high + lowest low) / 2 of prior session
    def calculate_value_midpoint
      return nil if @candles.size < 10

      # Use first half as "previous session" proxy
      prior_session_candles = @candles[0...(@candles.size / 2)]

      highest_high = prior_session_candles.pluck(:high).max
      lowest_low = prior_session_candles.pluck(:low).min

      (highest_high + lowest_low) / 2.0
    end

    # -------------------------------------------------------------------------
    # UTILITY METHODS
    # -------------------------------------------------------------------------

    # Calculate average candle range for gap significance threshold
    def calculate_average_range
      ranges = @candles.last(10).map { |c| c[:high] - c[:low] }
      ranges.sum / ranges.size.to_f
    end

    # Check if all values in array are in descending order
    def all_descending?(values)
      return false if values.size < 2

      values.each_cons(2).all? { |a, b| a > b }
    end

    # Check if all values in array are in ascending order
    def all_ascending?(values)
      return false if values.size < 2

      values.each_cons(2).all? { |a, b| a < b }
    end

    # Normalize candles to consistent hash format with symbol keys
    def normalize_candles(candles)
      return [] if candles.blank?

      candles.filter_map do |candle|
        if candle.is_a?(Hash)
          {
            open: extract_value(candle, :open),
            high: extract_value(candle, :high),
            low: extract_value(candle, :low),
            close: extract_value(candle, :close)
          }
        elsif candle.respond_to?(:open)
          # Struct or object with accessors
          {
            open: candle.open.to_f,
            high: candle.high.to_f,
            low: candle.low.to_f,
            close: candle.close.to_f
          }
        end
      end
    end

    # Extract value from hash with symbol or string key
    def extract_value(hash, key)
      (hash[key] || hash[key.to_s]).to_f
    end
  end
  # rubocop:enable Metrics/ClassLength
end
