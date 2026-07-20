# frozen_string_literal: true

module Indicators
  class Vortex < ApplicationService
    PERIOD = 14

    attr_reader :candles

    def initialize(candles)
      @candles = candles
    end

    def call
      return nil if candles.size < PERIOD + 1

      relevant = candles.last(PERIOD + 1)
      sum_tr = 0.0
      sum_vm_plus = 0.0
      sum_vm_minus = 0.0

      (1...relevant.size).each do |i|
        c = relevant[i]
        p = relevant[i - 1]

        tr = [
          c[:high] - c[:low],
          (c[:high] - p[:close]).abs,
          (c[:low] - p[:close]).abs
        ].max
        sum_tr += tr

        sum_vm_plus += (c[:high] - p[:low]).abs
        sum_vm_minus += (c[:low] - p[:high]).abs
      end

      vi_plus = sum_tr.positive? ? (sum_vm_plus / sum_tr).round(4) : 0.0
      vi_minus = sum_tr.positive? ? (sum_vm_minus / sum_tr).round(4) : 0.0

      state = if vi_plus > vi_minus
                :bullish
              elsif vi_minus > vi_plus
                :bearish
              else
                :neutral
              end

      {
        vi_plus: vi_plus,
        vi_minus: vi_minus,
        state: state,
        period: PERIOD
      }
    end

    # curr: pass an already-computed `call` result for current_candles to skip recomputing it.
    def self.crossover?(prev_candles, current_candles, curr: nil)
      prev = new(prev_candles).call
      curr ||= new(current_candles).call
      return false if prev.nil? || curr.nil?

      if curr[:state] == :bullish && prev[:state] != :bullish
        :bullish_crossover
      elsif curr[:state] == :bearish && prev[:state] != :bearish
        :bearish_crossover
      else
        :none
      end
    end
  end
end
