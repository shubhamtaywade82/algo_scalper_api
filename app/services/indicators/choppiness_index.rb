# frozen_string_literal: true

module Indicators
  class ChoppinessIndex < ApplicationService
    PERIOD = 14

    attr_reader :candles

    def initialize(candles)
      @candles = candles
    end

    def call
      return nil if candles.size < PERIOD + 1

      relevant = candles.last(PERIOD + 1)
      tr_sum = 0.0

      (1...relevant.size).each do |i|
        c = relevant[i]
        p = relevant[i - 1]
        tr = [
          c[:high] - c[:low],
          (c[:high] - p[:close]).abs,
          (c[:low] - p[:close]).abs
        ].max
        tr_sum += tr
      end

      period_candles = relevant.last(PERIOD)
      highest_high = period_candles.map { |c| c[:high] }.max # rubocop:disable Rails/Pluck
      lowest_low = period_candles.map { |c| c[:low] }.min # rubocop:disable Rails/Pluck
      range = highest_high - lowest_low

      chop = if range.positive? && tr_sum.positive?
               (100.0 * Math.log10(tr_sum / range) / Math.log10(PERIOD)).round(2)
             else
               100.0
             end

      regime = if chop < 38.0
                 :trending
               elsif chop > 61.0
                 :choppy
               else
                 :neutral
               end

      {
        value: chop,
        regime: regime,
        period: PERIOD
      }
    end
  end
end
