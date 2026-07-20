# frozen_string_literal: true

module Indicators
  class MoneyFlowIndex < ApplicationService
    PERIOD = 14

    attr_reader :candles

    def initialize(candles)
      @candles = candles
    end

    def call
      return nil if candles.size < PERIOD + 1

      relevant = candles.last(PERIOD + 1)
      positive_mf = 0.0
      negative_mf = 0.0
      prev_tp = nil

      relevant.each do |c|
        typical_price = (c[:high] + c[:low] + c[:close]) / 3.0
        raw_mf = typical_price * c[:volume].to_f

        if prev_tp
          if typical_price > prev_tp
            positive_mf += raw_mf
          elsif typical_price < prev_tp
            negative_mf += raw_mf
          end
        end

        prev_tp = typical_price
      end

      mfi_value = if negative_mf.zero?
                    100.0
                  else
                    ratio = positive_mf / negative_mf
                    (100.0 - (100.0 / (1.0 + ratio))).round(2)
                  end

      state = if mfi_value > 80
                :overbought
              elsif mfi_value < 20
                :oversold
              elsif mfi_value >= 50
                :bullish
              else
                :bearish
              end

      {
        value: mfi_value,
        state: state,
        period: PERIOD
      }
    end
  end
end
