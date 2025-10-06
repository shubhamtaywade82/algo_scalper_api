# frozen_string_literal: true

require "bigdecimal"

module Equities
  Signal = Struct.new(
    :direction,
    :ltp,
    :atr,
    :strength,
    :volume_ratio,
    :obv_direction,
    :stop_distance,
    keyword_init: true
  ) do
    def tradable?
      direction && direction != :hold
    end
  end

  # Generates trade signals for equity instruments based on the configured indicators.
  class SignalService
    MIN_ADX = BigDecimal("25")
    MIN_VOLUME_MULTIPLIER = BigDecimal("1.5")
    STOP_MULTIPLIER = BigDecimal("1.5")
    LOOKBACK = 120

    def initialize(
      data_fetcher: Trading::DataFetcherService.new,
      indicator_calculator: IndicatorCalculator.new
    )
      @data_fetcher = data_fetcher
      @indicator_calculator = indicator_calculator
    end

    def signal_for(instrument)
      candles = @data_fetcher.fetch_historical_data(
        security_id: instrument.security_id,
        exchange_segment: instrument.exchange_segment,
        interval: "1minute",
        lookback: LOOKBACK
      )
      return if candles.blank?

      indicators = @indicator_calculator.evaluate(candles)
      return unless indicators

      volume_ratio = indicators.volume_ratio
      obv_direction = indicators.obv_direction
      adx = indicators.adx
      direction = derive_direction(indicators)
      return if direction == :hold
      return unless adx && adx >= MIN_ADX
      return unless volume_ratio && volume_ratio >= MIN_VOLUME_MULTIPLIER
      return unless obv_direction == :bullish || obv_direction == :bearish

      ltp = candles.last[:close]
      atr = indicators.atr
      stop_distance = atr * STOP_MULTIPLIER

      Signal.new(
        direction: direction,
        ltp: ltp,
        atr: atr,
        strength: adx,
        volume_ratio: volume_ratio,
        obv_direction: obv_direction,
        stop_distance: stop_distance
      )
    end

    private

    def derive_direction(indicators)
      st_direction = indicators.supertrend_direction
      ema_fast = indicators.ema_fast
      ema_slow = indicators.ema_slow
      return :hold unless st_direction && ema_fast && ema_slow

      momentum = ema_fast > ema_slow

      case st_direction
      when :bullish
        momentum ? :long : :hold
      when :bearish
        momentum ? :hold : :short
      else
        :hold
      end
    end
  end
end
