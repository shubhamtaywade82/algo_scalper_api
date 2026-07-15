# frozen_string_literal: true

module Research
  class AuctionArchetypeClassifier
    # Predicts the archetype at the moment of breakout entry (no hindsight/lookahead leakage).
    # @param day_data [Hash] Daily candles and metrics
    # @param entry_idx [Integer] Minute index at breakout entry
    # @return [Symbol] Predicted archetype
    def self.predict(day_data, entry_idx)
      candles = day_data[:underlying_candles] || []
      return :open_auction if entry_idx.nil? || entry_idx < 15

      # Slice candles up to entry_idx so we have zero future knowledge
      known_candles = candles.first(entry_idx + 1)
      
      mock_day = day_data.merge(underlying_candles: known_candles)
      
      # If we are under 30 minutes of data, we classify with what is available
      if known_candles.size < 30
        open_price = known_candles.first[:open]
        close_now = known_candles.last[:close]
        
        # Simple predictive heuristics for early drive detection
        consecutive_direction = known_candles.last(3).all? { |c| c[:close] > c[:open] }
        if consecutive_direction && close_now > open_price + 20
          return :opening_drive
        elsif known_candles.last(3).all? { |c| c[:close] < c[:open] } && close_now < open_price - 20
          return :opening_drive
        end
        return :open_auction
      end

      classify(mock_day)
    end

    # Classifies a day's opening auction behavior into an Auction Market Theory archetype.
    # @param day_data [Hash] Daily candles and metrics
    # @return [Symbol] The classified archetype
    def self.classify(day_data)
      candles = day_data[:underlying_candles] || []
      return :open_auction if candles.size < 30

      first_30m = candles.first(30)
      first_15m = candles.first(15)
      next_15m = first_30m.drop(15)

      open_price = first_30m.first[:open]
      high_30m = first_30m.map { |c| c[:high] }.max
      low_30m = first_30m.map { |c| c[:low] }.min
      close_30m = first_30m.last[:close]

      # Gap Context
      gap_pct = day_data[:gap_pct] || 0.0
      prev_close = day_data[:prev_day_close] || open_price

      # Volatility context (ATR)
      atr = day_data[:atr] || 20.0
      range_30m = high_30m - low_30m

      # Directional drives
      first_15m_green = first_15m.count { |c| c[:close] > c[:open] }
      first_15m_red = first_15m.count { |c| c[:close] < c[:open] }

      # 1. Gap and Go vs Gap Fill
      if gap_pct.abs > 0.4 && prev_close > 0
        # Check if gap was filled in first 30m
        gap_filled = first_30m.any? do |c|
          gap_pct > 0 ? (c[:low] <= prev_close) : (c[:high] >= prev_close)
        end
        return gap_filled ? :gap_fill : :gap_and_go
      end

      # 2. Trend From Open (Continuous directional move from open)
      is_tfo_bullish = first_15m.first(5).all? { |c| c[:close] > c[:open] } && close_30m > open_price
      is_tfo_bearish = first_15m.first(5).all? { |c| c[:close] < c[:open] } && close_30m < open_price
      return :trend_from_open if is_tfo_bullish || is_tfo_bearish

      # 3. Opening Drive (Aggressive buying/selling, never retests open)
      never_retested_open = first_30m.drop(1).all? do |c|
        close_30m > open_price ? (c[:low] > open_price) : (c[:high] < open_price)
      end
      first_15m_directional = (first_15m_green >= 11) || (first_15m_red >= 11)
      return :opening_drive if never_retested_open && first_15m_directional

      # 4. Open Test Drive (Tests opposite side first, then drives)
      test_low_first = first_15m.first(5).any? { |c| c[:low] < open_price - 10 } && close_30m > open_price + 30
      test_high_first = first_15m.first(5).any? { |c| c[:high] > open_price + 10 } && close_30m < open_price - 30
      return :open_test_drive if test_low_first || test_high_first

      # 5. Open Rejection Reverse (Breaches range, then reverses sharply)
      breached_high_then_reversed = first_15m.any? { |c| c[:high] > open_price + 25 } && close_30m < open_price - 15
      breached_low_then_reversed = first_15m.any? { |c| c[:low] < open_price - 25 } && close_30m > open_price + 15
      return :open_rejection_reverse if breached_high_then_reversed || breached_low_then_reversed

      # 6. Failed Auction (Fakeout breakout outside 15m range)
      or_high_15m = first_15m.map { |c| c[:high] }.max
      or_low_15m = first_15m.map { |c| c[:low] }.min
      breached_high_then_failed = next_15m.any? { |c| c[:close] > or_high_15m } && close_30m < or_high_15m
      breached_low_then_failed = next_15m.any? { |c| c[:close] < or_low_15m } && close_30m > or_low_15m
      return :failed_auction if breached_high_then_failed || breached_low_then_failed

      # 7. Open Auction (Stays range-bound)
      if range_30m < atr * 0.8
        :open_auction
      else
        :open_auction # Fallback default
      end
    end
  end
end
