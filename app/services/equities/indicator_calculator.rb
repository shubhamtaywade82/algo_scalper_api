# frozen_string_literal: true

require "bigdecimal"

module Equities
  # Calculates price and volume indicators required for the intraday equity strategy.
  class IndicatorCalculator
    Result = Struct.new(
      :supertrend_direction,
      :supertrend_value,
      :adx,
      :atr,
      :volume_ratio,
      :obv_direction,
      :ema_fast,
      :ema_slow,
      keyword_init: true
    )

    MIN_CANDLES = 50
    DEFAULT_SUPERTREND_PERIOD = 10
    DEFAULT_SUPERTREND_MULTIPLIER = BigDecimal("3")
    DEFAULT_ADX_PERIOD = 14
    DEFAULT_VOLUME_PERIOD = 20
    FAST_EMA_PERIOD = 9
    SLOW_EMA_PERIOD = 21
    OBV_LOOKBACK = 20

    def initialize(
      supertrend_period: DEFAULT_SUPERTREND_PERIOD,
      supertrend_multiplier: DEFAULT_SUPERTREND_MULTIPLIER,
      adx_period: DEFAULT_ADX_PERIOD,
      volume_period: DEFAULT_VOLUME_PERIOD
    )
      @supertrend_period = supertrend_period
      @supertrend_multiplier = decimal(supertrend_multiplier)
      @adx_period = adx_period
      @volume_period = volume_period
    end

    def evaluate(candles)
      candles = Array(candles).compact
      return if candles.size < MIN_CANDLES

      atr_series = atr_list(candles, period: @supertrend_period)
      atr_value = atr_series.last
      return unless atr_value

      st = supertrend(candles, atr_series)
      adx_value = adx(candles, period: @adx_period)
      ema_fast = ema(candles.map { |c| c[:close] }, FAST_EMA_PERIOD)
      ema_slow = ema(candles.map { |c| c[:close] }, SLOW_EMA_PERIOD)
      volume_ratio = current_volume_ratio(candles, period: @volume_period)
      obv_direction = obv_trend(candles, lookback: OBV_LOOKBACK)

      Result.new(
        supertrend_direction: st[:direction],
        supertrend_value: st[:value],
        adx: adx_value,
        atr: atr_value,
        volume_ratio: volume_ratio,
        obv_direction: obv_direction,
        ema_fast: ema_fast,
        ema_slow: ema_slow
      )
    end

    private

    def supertrend(candles, atr_series)
      final_upper = []
      final_lower = []
      directions = []
      initialized = false

      candles.each_with_index do |candle, index|
        atr_value = atr_series[index]
        next unless atr_value

        hl2 = (decimal(candle[:high]) + decimal(candle[:low])) / 2
        basic_upper = hl2 + (@supertrend_multiplier * atr_value)
        basic_lower = hl2 - (@supertrend_multiplier * atr_value)

        unless initialized
          final_upper << basic_upper
          final_lower << basic_lower
          directions << (decimal(candle[:close]) >= basic_lower ? :bullish : :bearish)
          initialized = true
          next
        end

        prev_close = decimal(candles[index - 1][:close])
        prev_final_upper = final_upper.last
        prev_final_lower = final_lower.last

        final_upper << if basic_upper < prev_final_upper || prev_close > prev_final_upper
          basic_upper
        else
          prev_final_upper
        end

        final_lower << if basic_lower > prev_final_lower || prev_close < prev_final_lower
          basic_lower
        else
          prev_final_lower
        end

        close = decimal(candle[:close])
        if close > final_upper.last
          directions << :bullish
          final_upper[-1] = final_lower.last
        elsif close < final_lower.last
          directions << :bearish
          final_lower[-1] = final_upper.last
        else
          directions << directions.last
        end
      end

      return { direction: :hold, value: nil } if final_upper.empty? || final_lower.empty?

      last_direction = directions.last || :hold
      last_value = if last_direction == :bearish
        final_upper.last
      else
        final_lower.last
      end

      { direction: last_direction, value: last_value }
    end

    def adx(candles, period: DEFAULT_ADX_PERIOD)
      return if candles.size < period + 1

      trs = []
      plus_dm = []
      minus_dm = []

      candles.each_cons(2) do |prev, curr|
        curr_high = decimal(curr[:high])
        curr_low = decimal(curr[:low])
        prev_close = decimal(prev[:close])
        prev_high = decimal(prev[:high])
        prev_low = decimal(prev[:low])

        trs << [ curr_high - curr_low, (curr_high - prev_close).abs, (curr_low - prev_close).abs ].compact.max

        up_move = curr_high - prev_high
        down_move = prev_low - curr_low

        plus_dm << (up_move > down_move && up_move.positive? ? up_move : BigDecimal("0"))
        minus_dm << (down_move > up_move && down_move.positive? ? down_move : BigDecimal("0"))
      end

      return if trs.size < period

      tr_smooth = smoothed_series(trs, period)
      plus_dm_smooth = smoothed_series(plus_dm, period)
      minus_dm_smooth = smoothed_series(minus_dm, period)

      plus_di = []
      minus_di = []
      tr_smooth.each_with_index do |tr_value, idx|
        next unless tr_value && tr_value.nonzero?

        plus_di << (BigDecimal("100") * plus_dm_smooth[idx] / tr_value)
        minus_di << (BigDecimal("100") * minus_dm_smooth[idx] / tr_value)
      end

      dx = plus_di.each_with_index.map do |plus, idx|
        minus = minus_di[idx]
        next unless plus && minus

        denominator = (plus + minus)
        next if denominator.zero?

        ((plus - minus).abs * BigDecimal("100")) / denominator
      end.compact

      return if dx.size < period

      smoothed_series(dx, period).last
    end

    def smoothed_series(values, period)
      result = []
      return result if values.size < period

      initial = values.first(period).sum(BigDecimal("0"))
      result << initial / period

      values.drop(period).each do |value|
        prev = result.last
        result << ((prev * (period - 1)) + value) / period
      end

      result
    end

    def ema(values, period)
      values = Array(values).compact
      return if values.size < period

      values = values.map { |value| decimal(value) }
      multiplier = BigDecimal("2") / (period + 1)
      ema_values = []

      values.each_with_index do |value, index|
        if index < period - 1
          ema_values << nil
          next
        elsif index == period - 1
          ema_values << values.first(period).sum(BigDecimal("0")) / period
          next
        end

        previous = ema_values.last
        ema_values << ((value - previous) * multiplier) + previous
      end

      ema_values.last
    end

    def current_volume_ratio(candles, period: DEFAULT_VOLUME_PERIOD)
      return if candles.size < period

      recent = candles.last(period)
      volumes = recent.map { |c| c[:volume].to_f }
      return if volumes.any?(&:zero?)

      current_volume = volumes.last
      avg_volume = volumes.sum / period.to_f
      return if avg_volume.zero?

      BigDecimal(current_volume.to_s) / BigDecimal(avg_volume.to_s)
    end

    def obv_trend(candles, lookback: OBV_LOOKBACK)
      closes = candles.map { |c| decimal(c[:close]) }
      volumes = candles.map { |c| BigDecimal(c[:volume].to_f.to_s) }
      obv = [ BigDecimal("0") ]

      closes.each_cons(2).with_index do |(prev_close, curr_close), index|
        change =
          if curr_close > prev_close
            volumes[index + 1]
          elsif curr_close < prev_close
            -volumes[index + 1]
          else
            BigDecimal("0")
          end
        obv << obv.last + change
      end

      return :neutral if obv.size <= lookback

      obv.last > obv[-lookback] ? :bullish : :bearish
    end

    def atr_list(candles, period: DEFAULT_SUPERTREND_PERIOD)
      return [] if candles.size < period + 1

      trs = []
      atr_values = []

      candles.each_cons(2).with_index do |(prev, curr), index|
        curr_high = decimal(curr[:high])
        curr_low = decimal(curr[:low])
        prev_close = decimal(prev[:close])

        tr = [ curr_high - curr_low, (curr_high - prev_close).abs, (curr_low - prev_close).abs ].compact.max
        trs << tr

        next if trs.size < period

        if atr_values.empty?
          atr_values << trs.first(period).sum(BigDecimal("0")) / period
        else
          atr_values << ((atr_values.last * (period - 1)) + tr) / period
        end
      end

      # align with candles length by padding initial nils
      padding = Array.new(candles.size - atr_values.size, nil)
      padding.concat(atr_values)
    end

    def decimal(value)
      return BigDecimal("0") if value.nil?

      BigDecimal(value.to_s)
    end
  end
end
