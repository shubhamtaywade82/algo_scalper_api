# frozen_string_literal: true

module AlgoScalper
  module Regime
    class Engine
      attr_reader :config

      def initialize(config = {})
        @config = {
          vwap_periods: [5, 15, 60],
          ema_periods: [9, 20, 50],
          rsi_period: 14,
          atr_period: { |period: 14,
          lookback_bars: 100
        }.merge(config)

        @candle_series = {}
      end

      def update(candle, symbol)
        @candle_series[symbol] ||= CandleSeries.new(@config[:lookback_bars])
        @candle_series[symbol].add(candle)
      end

      def regime(symbol)
        series = @candle_series[symbol]
        return :unknown unless series&.ready?

        bullish_score = 0
        bearish_score = 0

        # VWAP position
        bullish_score += 20 if series.price > series.vwap(15)
        bearish_score += 20 if series.price < series.vwap(15)

        # EMA alignment
        emas = @config[:ema_periods].map { |p| series.ema(p) }.compact
        bullish_score += 25 if emas.size >= 2 && emas[0] > emas[1] && emas[1] > emas[2]
        bearish_score += 25 if emas.size >= 2 && emas[0] < emas[1] && emas[1] < emas[2]

        # RSI
        rsi = series.rsi(@config[:rsi_period])
        bullish_score += 10 if rsi && rsi > 55
        bearish_score += 10 if rsi && rsi < 45

        # ATR expansion
        atr = series.atr(@config[:atr_period])
        atr_ratio = atr / series.atr(50) if atr && series.atr(50)
        bullish_score += 10 if atr_ratio && atr_ratio > 1.2
        bearish_score += 10 if atr_ratio && atr_ratio > 1.2

        # Trend consistency
        bullish_score += 15 if series.trend_consistency > 0.7
        bearish_score += 15 if series.trend_consistency < -0.7

        total = bullish_score + bearish_score
        return :neutral if total < 40

        if bullish_score > bearish_score
          bullish_score >= 70 ? :strong_bullish : :bullish
        else
          bearish_score >= 70 ? :strong_bearish : :bearish
        end
      end

      def trend_strength(symbol)
        series = @candle_series[symbol]
        return 0 unless series&.ready?

        ema9 = series.ema(9)
        ema20 = series.ema(20)
        ema50 = series.ema(50)

        return 0 unless ema9 && ema20 && ema50

        distance_9_20 = ((ema9 - ema20).abs / ema20) * 100
        distance_20_50 = ((ema20 - ema50).abs / ema50) * 100

        (distance_9_20 + distance_20_50).round(2)
      end

      def vwap_distance(symbol)
        series = @candle_series[symbol]
        return nil unless series&.ready?

        vwap = series.vwap(15)
        return nil unless vwap && vwap > 0

        ((series.price - vwap) / vwap * 100).round(2)
      end

      def atr(symbol)
        @candle_series[symbol]&.atr(@config[:atr_period])
      end

      def rsi(symbol)
        @candle_series[symbol]&.rsi(@config[:rsi_period])
      end

      class CandleSeries
        def initialize(max_bars)
          @max_bars = max_bars
          @candles = []
          @price = 0.0
        end

        def add(candle)
          @candles << candle
          @candles.shift if @candles.size > @max_bars
          @price = candle[:close] || candle[:c]
        end

        def ready?
          @candles.size >= 50
        end

        def price
          @price
        end

        def vwap(period = nil)
          data = period ? @candles.last(period) : @candles
          return nil if data.empty?

          typical_prices = data.map { |c| (c[:high] + c[:low] + c[:close]) / 3.0 }
          volumes = data.map { |c| c[:volume] || c[:v] || 1 }

          return nil if volumes.sum.zero?

          (typical_prices.zip(volumes).map { |tp, v| tp * v }.sum / volumes.sum).round(2)
        end

        def ema(period)
          return nil if @candles.size < period

          k = 2.0 / (period + 1)
          closes = @candles.map { |c| c[:close] || c[:c] }

          ema = closes.first
          closes[1..].each { |c| ema = (c - ema) * k + ema }
          ema.round(2)
        end

        def rsi(period)
          return nil if @candles.size < period + 1

          closes = @candles.map { |c| c[:close] || c[:c] }
          gains = []
          losses = []

          (1...closes.size).each do |i|
            diff = closes[i] - closes[i - 1]
            gains << [diff, 0].max
            losses << [-diff, 0].max
          end

          avg_gain = gains.first(period).sum / period
          avg_loss = losses.first(period).sum / period

          (period...gains.size).each do |i|
            avg_gain = (avg_gain * (period - 1) + gains[i]) / period
            avg_loss = (avg_loss * (period - 1) + losses[i]) / period
          end

          return 50.0 if avg_loss.zero?

          rs = avg_gain / avg_loss
          (100 - (100 / (1 + rs))).round(2)
        end

        def atr(period)
          return nil if @candles.size < period + 1

          trs = []
          (1...@candles.size).each do |i|
            h = @candles[i][:high] || @candles[i][:h]
            l = @candles[i][:low] || @candles[i][:l]
            pc = @candles[i - 1][:close] || @candles[i - 1][:c]

            tr = [h - l, (h - pc).abs, (l - pc).abs].max
            trs << tr
          end

          trs.last(period).sum / period
        end

        def trend_consistency
          return 0 if @candles.size < 20

          closes = @candles.last(20).map { |c| c[:close] || c[:c] }
          up = closes.each_cons(2).count { |a, b| b > a }
          down = 20 - up

          ((up - down) / 20.0).round(2)
        end
      end
    end
  end
end