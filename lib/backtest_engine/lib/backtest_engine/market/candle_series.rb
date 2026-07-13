module BacktestEngine
  module Market
    class CandleSeries
      attr_reader :candles

      def initialize(candles)
        @candles = Array(candles).sort
        raise ArgumentError, "Empty series" if @candles.empty?

        @cache = {}
      end

      # Basic access

      def [](index)
        candles[index]
      end

      def last(count = 1)
        count == 1 ? candles.last : candles.last(count)
      end

      def size
        candles.size
      end

      def each(&block)
        candles.each(&block)
      end

      # Moving averages

      def ema(period)
        fetch_from_cache(:ema, period) do
          k = 2.0 / (period + 1)
          values = []

          candles.each_with_index do |candle, index|
            if index.zero?
              values << candle.close
            else
              values << (candle.close * k + values[-1] * (1 - k))
            end
          end

          values
        end
      end

      # RSI

      def rsi(period = 14)
        fetch_from_cache(:rsi, period) do
          gains = []
          losses = []

          closes.each_cons(2) do |previous, current|
            change = current - previous
            gains << [change, 0].max
            losses << [change.abs, 0].min.abs
          end

          avg_gain = gains.first(period).sum / period.to_f
          avg_loss = losses.first(period).sum / period.to_f

          result = Array.new(period)

          gains.each_index do |index|
            next if index < period

            avg_gain = ((avg_gain * (period - 1)) + gains[index]) / period
            avg_loss = ((avg_loss * (period - 1)) + losses[index]) / period

            rs = avg_loss.zero? ? 100 : avg_gain / avg_loss
            result << (100 - (100 / (1 + rs)))
          end

          result
        end
      end

      # ATR

      def atr(period = 14)
        fetch_from_cache(:atr, period) do
          trs = []

          candles.each_with_index do |candle, index|
            if index.zero?
              trs << candle.range
            else
              previous = candles[index - 1]
              tr = [
                candle.high - candle.low,
                (candle.high - previous.close).abs,
                (candle.low - previous.close).abs
              ].max

              trs << tr
            end
          end

          values = []
          values << trs.first(period).sum / period.to_f

          trs[period..].each do |tr|
            values << ((values.last * (period - 1)) + tr) / period
          end

          values
        end
      end

      # Structure (BOS / CHOCH)

      def structure
        fetch_from_cache(:structure) do
          result = []

          (2...size).each do |index|
            previous = candles[index - 1]
            current = candles[index]

            if current.higher_high_than?(previous) && current.low > previous.low
              result << :bullish
            elsif current.lower_low_than?(previous) && current.high < previous.high
              result << :bearish
            else
              result << :range
            end
          end

          result
        end
      end

      def bos?(index)
        return false if index < 2

        current = candles[index]
        previous = candles[index - 1]

        current.high > previous.high || current.low < previous.low
      end

      def choch?(index)
        return false if index < 3

        previous_trend = structure[index - 2]
        current_trend = structure[index - 1]

        previous_trend != current_trend && current_trend != :range
      end

      # Swing points

      def swing_high?(index, lookback: 3)
        return false if index < lookback || index >= size - lookback

        high = candles[index].high
        left = candles[(index - lookback)...index].all? { |candle| high > candle.high }
        right = candles[(index + 1)..(index + lookback)].all? { |candle| high > candle.high }

        left && right
      end

      def swing_low?(index, lookback: 3)
        return false if index < lookback || index >= size - lookback

        low = candles[index].low
        left = candles[(index - lookback)...index].all? { |candle| low < candle.low }
        right = candles[(index + 1)..(index + lookback)].all? { |candle| low < candle.low }

        left && right
      end

      # Pullback detection

      def pullback?(index, ema_period: 20)
        return false if index < ema_period

        ema_value = ema(ema_period)[index]
        candle = candles[index]

        candle.low <= ema_value && candle.close > ema_value
      end

      def bearish_pullback?(index, ema_period: 20)
        return false if index < ema_period

        ema_value = ema(ema_period)[index]
        candle = candles[index]

        candle.high >= ema_value && candle.close < ema_value
      end

      def volume_ratio(index, period:)
        return 1.0 if index < period

        window = candles[(index - period)...index]
        return 1.0 if volume_unavailable?(window)

        average = window.sum(&:volume) / period.to_f
        return 1.0 if average.zero?

        candles[index].volume.to_f / average
      end

      # VWAP (Intraday resets)
      def vwap
        fetch_from_cache(:vwap) do
          values = []
          cum_pv = 0.0
          cum_vol = 0.0
          last_date = nil

          candles.each do |candle|
            date = candle.timestamp.to_date
            if last_date != date
              cum_pv = 0.0
              cum_vol = 0.0
              last_date = date
            end

            tp = (candle.high + candle.low + candle.close) / 3.0
            cum_pv += tp * candle.volume
            cum_vol += candle.volume

            values << (cum_vol.zero? ? candle.close : cum_pv / cum_vol)
          end
          values
        end
      end

      # Donchian Channels (returns previous N candles high/low)
      def donchian_high(period = 20)
        fetch_from_cache(:donchian_high, period) do
          values = []
          candles.each_with_index do |candle, index|
            if index.zero?
              values << candle.high
            else
              start = [0, index - period].max
              values << highs[start...index].max
            end
          end
          values
        end
      end

      def donchian_low(period = 20)
        fetch_from_cache(:donchian_low, period) do
          values = []
          candles.each_with_index do |candle, index|
            if index.zero?
              values << candle.low
            else
              start = [0, index - period].max
              values << lows[start...index].min
            end
          end
          values
        end
      end

      # Supertrend (returns { supertrend: Array, trend: Array<Boolean> })
      def supertrend(period = 10, multiplier = 3.0)
        fetch_from_cache(:supertrend, [period, multiplier]) do
          atr_values = atr(period)
          st_values = []
          upper_bands = []
          lower_bands = []
          trend = [] # true for bullish, false for bearish

          candles.each_with_index do |candle, index|
            atr_val = atr_values[index] || 0.0
            mid = (candle.high + candle.low) / 2.0
            basic_ub = mid + (multiplier * atr_val)
            basic_lb = mid - (multiplier * atr_val)

            if index.zero?
              upper_bands << basic_ub
              lower_bands << basic_lb
              st_values << basic_ub
              trend << false
            else
              prev_close = candles[index - 1].close
              prev_ub = upper_bands[index - 1]
              prev_lb = lower_bands[index - 1]

              ub = (basic_ub < prev_ub || prev_close > prev_ub) ? basic_ub : prev_ub
              lb = (basic_lb > prev_lb || prev_close < prev_lb) ? basic_lb : prev_lb

              upper_bands << ub
              lower_bands << lb

              prev_st = st_values[index - 1]
              prev_trend = trend[index - 1]

              curr_trend = prev_trend
              if prev_trend && candle.close < lb
                curr_trend = false
              elsif !prev_trend && candle.close > ub
                curr_trend = true
              end

              trend << curr_trend
              st_values << (curr_trend ? lb : ub)
            end
          end

          { supertrend: st_values, trend: trend }
        end
      end

      # Helpers

      def closes
        @closes ||= candles.map(&:close)
      end

      def highs
        @highs ||= candles.map(&:high)
      end

      def lows
        @lows ||= candles.map(&:low)
      end

      private

      def volume_unavailable?(window)
        window.all? { |candle| candle.volume.to_i.zero? }
      end

      def fetch_from_cache(key, parameter = nil)
        cache_key = [key, parameter]
        return @cache[cache_key] if @cache.key?(cache_key)

        @cache[cache_key] = yield
      end
    end
  end
end

