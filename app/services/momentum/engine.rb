# frozen_string_literal: true

module AlgoScalper
  module Momentum
    class Engine
      attr_reader :config

      def initialize(config = {})
        @config = {
          ema_fast: 9,
          ema_slow: 21,
          rsi_period: 14,
          roc_period: 9,
          lookback: 100
        }.merge(config)

        @candles = []
      end

      def update(candle)
        @candles << candle
        @candles.shift if @candles.size > @config[:lookback]
      end

      def bullish_momentum?
        score > 0
      end

      def bearish_momentum?
        score < 0
      end

      def score
        return 0 unless ready?

        s = 0

        # EMA slope
        s += 25 if ema_slope > 0
        s -= 25 if ema_slope < 0

        # Price vs VWAP
        s += 20 if price > vwap
        s -= 20 if price < vwap

        # RSI
        s += 15 if rsi && rsi > 55
        s -= 15 if rsi && rsi < 45

        # ROC
        s += 15 if roc && roc > 0
        s -= 15 if roc && roc < 0

        # ATR expansion
        s += 10 if atr_expanding?
        s -= 10 if atr_contracting?

        s
      end

      def accelerating?
        return false unless ready?

        ema_slope > previous_ema_slope
      end

      def dying?
        return false unless ready?

        ema_slope < previous_ema_slope && (rsi || 50).between?(45, 55)
      end

      def ema_slope
        return 0 unless ready?

        fast = ema(@config[:ema_fast])
        slow = ema(@config[:ema_slow])
        return 0 unless fast && slow

        ((fast - slow) / slow * 100).round(4)
      end

      def previous_ema_slope
        return 0 if @candles.size < @config[:ema_slow] + 5

        candles = @candles[-(@config[:ema_slow] + 5)..-6]
        return 0 unless candles.size >= @config[:ema_slow]

        fast = calculate_ema(candles, @config[:ema_fast])
        slow = calculate_ema(candles, @config[:ema_slow])
        return 0 unless fast && slow

        ((fast - slow) / slow * 100).round(4)
      end

      def vwap
        return nil unless ready?

        typical = @candles.map { |c| ((c[:high] || c[:h]) + (c[:low] || c[:l]) + (c[:close] || c[:c])) / 3.0 }
        vols = @candles.map { |c| c[:volume] || c[:v] || 1 }
        (typical.zip(vols).map { |tp, v| tp * v }.sum / vols.sum).round(2)
      end

      def price
        @candles.last[:close] || @candles.last[:c]
      end

      def rsi
        return nil unless @candles.size >= @config[:rsi_period] + 1

        closes = @candles.map { |c| c[:close] || c[:c] }
        gains = []
        losses = []

        (1...closes.size).each do |i|
          diff = closes[i] - closes[i - 1]
          gains << [diff, 0].max
          losses << [-diff, 0].max
        end

        period = @config[:rsi_period]
        avg_gain = gains.first(period).sum / period
        avg_loss = losses.first(period).sum / period

        (period...gains.size).each do |i|
          avg_gain = (avg_gain * (period - 1) + gains[i]) / period
          avg_loss = (avg_loss * (period - 1) + losses[i]) / period
        end

        return 50.0 if avg_loss.zero?

        rs = avg_gain / avg_loss
        100 - (100 / (1 + rs))
      end

      def roc
        return nil unless @candles.size >= @config[:roc_period] + 1

        current = price
        past = @candles[-(@config[:roc_period] + 1)][:close] || @candles[-(@config[:roc_period] + 1)][:c]
        return nil unless past && past > 0

        ((current - past) / past * 100).round(2)
      end

      def atr_expanding?
        return false unless @candles.size >= 20

        current_atr = atr(14)
        past_atr = atr(14, offset: 5)
        return false unless current_atr && past_atr

        current_atr > past_atr * 1.1
      end

      def atr_contracting?
        return false unless @candles.size >= 20

        current_atr = atr(14)
        past_atr = atr(14, offset: 5)
        return false unless current_atr && past_atr

        current_atr < past_atr * 0.9
      end

      def atr(period, offset: 0)
        return nil if @candles.size < period + 1 + offset

        candles = offset > 0 ? @candles[-(period + offset)..-(offset + 1)] : @candles.last(period + 1)
        return nil if candles.size < period + 1

        trs = []
        (1...candles.size).each do |i|
          h = candles[i][:high] || candles[i][:h]
          l = candles[i][:low] || candles[i][:l]
          pc = candles[i - 1][:close] || candles[i - 1][:c]
          trs << [h - l, (h - pc).abs, (l - pc).abs].max
        end

        trs.sum / period
      end

      def ema(period)
        calculate_ema(@candles, period)
      end

      def calculate_ema(candles, period)
        return nil if candles.size < period

        k = 2.0 / (period + 1)
        closes = candles.map { |c| c[:close] || c[:c] }

        ema = closes.first
        closes[1..].each { |c| ema = (c - ema) * k + ema }
        ema
      end

      def ready?
        @candles.size >= @config[:lookback]
      end
    end
  end
end