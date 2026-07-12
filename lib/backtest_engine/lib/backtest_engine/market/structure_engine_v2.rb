# frozen_string_literal: true

module BacktestEngine
  module Market
    class StructureEngineV2
      Swing = Struct.new(:index, :price, :type, keyword_init: true) # type: :high / :low

      attr_reader :series

      def initialize(series)
        @series = series
        @swings = detect_swings
      end

      def structure_at(index)
        return :range if index < min_lookback

        last_bos = last_bos_before(index)
        last_choch = last_choch_before(index)

        if last_choch && last_choch[:index] > (last_bos&.dig(:index) || -1)
          return last_choch[:direction]
        end

        return last_bos[:direction] if last_bos

        :range
      end

      def bos_events
        @bos_events ||= detect_bos
      end

      def choch_events
        @choch_events ||= detect_choch
      end

      def liquidity_sweeps
        @liquidity_sweeps ||= detect_liquidity_sweeps
      end

      private

      def min_lookback
        lookback = 3
        lookback * 2 + 1
      end

      def detect_bos
        events = []

        @swings.each_cons(2) do |prev, curr|
          next if prev.type == curr.type

          if curr.type == :high && curr.price > prev.price
            events << { index: curr.index, direction: :bullish }
          elsif curr.type == :low && curr.price < prev.price
            events << { index: curr.index, direction: :bearish }
          end
        end

        events
      end

      def detect_choch
        events = []
        trend = nil

        bos_events.each do |bos|
          if trend.nil?
            trend = bos[:direction]
            next
          end

          if bos[:direction] != trend
            events << { index: bos[:index], direction: bos[:direction] }
            trend = bos[:direction]
          end
        end

        events
      end

      def detect_liquidity_sweeps
        sweeps = []

        @swings.each_cons(2) do |prev, curr|
          candle = series[curr.index]
          next unless candle

          if curr.type == :high &&
             candle.high > prev.price &&
             candle.close < prev.price
            sweeps << {
              index: curr.index,
              type: :buy_side_liquidity,
              direction: :bearish
            }
          end

          if curr.type == :low &&
             candle.low < prev.price &&
             candle.close > prev.price
            sweeps << {
              index: curr.index,
              type: :sell_side_liquidity,
              direction: :bullish
            }
          end
        end

        sweeps
      end

      def detect_swings(lookback: 3)
        swings = []
        range_start = lookback
        range_end = series.size - lookback - 1

        range_start.upto(range_end) do |i|
          if swing_high?(i, lookback)
            swings << Swing.new(index: i, price: series[i].high, type: :high)
          elsif swing_low?(i, lookback)
            swings << Swing.new(index: i, price: series[i].low, type: :low)
          end
        end

        swings
      end

      def swing_high?(index, lookback)
        high = series[index].high
        left = (index - lookback...index).all? { |j| high > series[j].high }
        right = (index + 1..index + lookback).all? { |j| high > series[j].high }
        left && right
      end

      def swing_low?(index, lookback)
        low = series[index].low
        left = (index - lookback...index).all? { |j| low < series[j].low }
        right = (index + 1..index + lookback).all? { |j| low < series[j].low }
        left && right
      end

      def last_bos_before(index)
        bos_events.reverse.find { |e| e[:index] < index }
      end

      def last_choch_before(index)
        choch_events.reverse.find { |e| e[:index] < index }
      end
    end
  end
end
