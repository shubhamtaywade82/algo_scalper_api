# frozen_string_literal: true

module Smc
  # Market structure extractor for CandleSeries
  # Responsibilities:
  # - Swing high / low detection
  # - Break of structure (BOS)
  # - Change of character (CHOCH)
  # - Order blocks (OB)
  # - Fair value gaps (FVG)
  # - Liquidity sweep detection
  #
  # Designed to be deterministic, unit-testable, and defensive.
  class Structure
    attr_reader :series, :candles, :interval

    SWING_LOOKBACK = 5
    FVG_LOOKBACK = 3
    DEFAULT_ATR_PERIOD = 14

    def initialize(series, interval: '5')
      if series.nil?
        raise ArgumentError, "CandleSeries is nil. Check if instrument.candle_series(interval: '#{interval}') returned data. " \
                            "This usually means OHLC data fetch failed - check DhanHQ API parameters and date ranges."
      end
      raise ArgumentError, "CandleSeries required (got #{series.class})" unless series.respond_to?(:candles)
      @series = series
      @candles = series.candles || []
      @interval = interval.to_s
    end

    # Returns an array of swing points [{type: :swing_high/:swing_low, index:, price:}]
    def swings(lookback: 200)
      res = []
      return res if candles.size < 5

      (2...(candles.size - 2)).each do |i|
        ch = candles[i]
        prev = candles[i - 1]
        nxt  = candles[i + 1]
        if ch.high > prev.high && ch.high > nxt.high
          res << { type: :swing_high, index: i, price: ch.high }
        elsif ch.low < prev.low && ch.low < nxt.low
          res << { type: :swing_low, index: i, price: ch.low }
        end
      end

      res.last(lookback)
    end

    # Last candle (nil safe)
    def last_candle
      candles.last
    end

    # ATR based tick buffer (float)
    def tick_buffer(atr_period: DEFAULT_ATR_PERIOD)
      atr = safe_call_series(:atr, atr_period) || 0.0
      (atr.to_f * 0.25).abs
    end

    # Break of Structure detection: returns hash or nil
    def break_of_structure
      s = swings(lookback: 300)
      return nil if s.empty? || last_candle.nil?

      last_close = last_candle.close

      last_high = s.reverse.find { |x| x[:type] == :swing_high }
      last_low  = s.reverse.find { |x| x[:type] == :swing_low }

      if last_high && last_close > last_high[:price] + tick_buffer
        { type: :bos_bull, level: last_high[:price], swing_index: last_high[:index] }
      elsif last_low && last_close < last_low[:price] - tick_buffer
        { type: :bos_bear, level: last_low[:price], swing_index: last_low[:index] }
      end
    end

    # CHOCH detection: requires a BOS present and checks for the first opposite invalidation
    def choch
      bos = break_of_structure
      return nil unless bos

      s = swings(lookback: 500)
      return nil if s.empty?

      if bos[:type] == :bos_bull
        prev_low = s.reverse.find { |x| x[:type] == :swing_low }
        return nil unless prev_low
        # CHOCH: price moved below previous swing low after a bullish BOS
        if last_candle.close < prev_low[:price] - tick_buffer
          { type: :choch_bear, level: prev_low[:price], index: prev_low[:index] }
        end
      else
        prev_high = s.reverse.find { |x| x[:type] == :swing_high }
        return nil unless prev_high
        if last_candle.close > prev_high[:price] + tick_buffer
          { type: :choch_bull, level: prev_high[:price], index: prev_high[:index] }
        end
      end
    end

    # Order Block: last opposite-direction candle cluster before BOS
    # Returns single OB hash or nil: { type: :bull_ob/:bear_ob, index:, high:, low: }
    def order_block(bos_info)
      return nil unless bos_info && bos_info[:swing_index]

      idx = [bos_info[:swing_index], candles.size - 1].min
      (idx - 1).downto(1) do |k|
        c = candles[k]
        # bullish BOS: search for last bearish candle as OB
        if bos_info[:type] == :bos_bull && c.close < c.open
          return { type: :bull_ob, index: k, high: c.high, low: c.low }
        elsif bos_info[:type] == :bos_bear && c.close > c.open
          return { type: :bear_ob, index: k, high: c.high, low: c.low }
        end
      end
      nil
    end

    # Fair Value Gaps (three-bar imbalance). Return array of FVGs
    def fvgs
      arr = []
      return arr if candles.size < 3
      (2...candles.size).each do |i|
        if candles[i].low > candles[i - 2].high
          arr << { type: :bull_fvg, start_index: i - 2, end_index: i, top: candles[i - 2].high, bottom: candles[i].low }
        elsif candles[i].high < candles[i - 2].low
          arr << { type: :bear_fvg, start_index: i - 2, end_index: i, top: candles[i].high, bottom: candles[i - 2].low }
        end
      end
      arr
    end

    # Returns last FVG or nil
    def last_fvg
      fvgs.last
    end

    # Detect liquidity sweep in last N candles. Returns {bull: bool, bear: bool}
    def liquidity_sweep?(lookback: 20)
      return { bull: false, bear: false } if candles.size < 3
      recent = candles.last([candles.size, lookback].min)
      recent_high = recent.map(&:high).max
      recent_low  = recent.map(&:low).min
      last = last_candle
      return { bull: false, bear: false } unless last

      buff = tick_buffer
      bull = (last.low < (recent_low - buff)) && (last.close > recent_low)
      bear = (last.high > (recent_high + buff)) && (last.close < recent_high)
      { bull: bull, bear: bear }
    end

    # Returns boolean: true if last price tapped OB or FVG (mitigation)
    def mitigated?(ob: nil, fvg: nil)
      return false if last_candle.nil?
      lc = last_candle.close
      if ob
        if ob[:type] == :bull_ob
          return true if lc >= ob[:low] - tick_buffer && lc <= ob[:high] + tick_buffer
        elsif ob[:type] == :bear_ob
          return true if lc <= ob[:high] + tick_buffer && lc >= ob[:low] - tick_buffer
        end
      elsif fvg
        if fvg[:type] == :bull_fvg
          return true if lc <= fvg[:bottom] + tick_buffer
        elsif fvg[:type] == :bear_fvg
          return true if lc >= fvg[:top] - tick_buffer
        end
      end
      false
    end

    # Helper: safe call series methods returning nil on failure
    def safe_call_series(method, *args)
      return nil unless series.respond_to?(method)
      series.public_send(method, *args)
    rescue StandardError => e
      Rails.logger.debug { "[Smc::Structure] safe_call_series #{method} failed: #{e.message}" }
      nil
    end
  end
end
