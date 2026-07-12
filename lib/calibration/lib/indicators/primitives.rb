# frozen_string_literal: true

module Indicators
  # ta.rsi() port — Wilder's RSI using RMA smoothing
  # Identical to Pine: rsi = 100 - 100 / (1 + rma(gain) / rma(loss))
  class RSI
    def initialize(length: 14)
      @length = length
      @alpha  = 1.0 / @length
    end

    # @param closes [Array<Float>]
    # @return [Array<Float|nil>]
    def calculate(closes)
      results = [nil]
      rma_gain = rma_loss = nil

      closes.each_cons(2).with_index do |(prev, curr), _i|
        change = curr - prev
        gain   = change > 0 ? change : 0.0
        loss   = change < 0 ? change.abs : 0.0

        if rma_gain.nil?
          rma_gain = gain
          rma_loss = loss
          results << nil
          next
        end

        rma_gain = @alpha * gain + (1 - @alpha) * rma_gain
        rma_loss = @alpha * loss + (1 - @alpha) * rma_loss

        rsi = rma_loss.zero? ? 100.0 : 100.0 - (100.0 / (1.0 + rma_gain / rma_loss))
        results << rsi.round(4)
      end

      results
    end
  end

  # ta.atr() port — Wilder's ATR using RMA
  # TR = max(H-L, |H-prevC|, |L-prevC|)
  # ATR = RMA(TR, length)
  class ATR
    def initialize(length: 14)
      @length = length
      @alpha  = 1.0 / @length
    end

    # @param bars [Array<Hash>] :high, :low, :close
    # @return [Array<Float|nil>]
    def calculate(bars)
      results = [nil]
      rma     = nil

      bars.each_cons(2) do |prev, curr|
        tr = [
          curr[:high] - curr[:low],
          (curr[:high] - prev[:close]).abs,
          (curr[:low]  - prev[:close]).abs
        ].max

        rma = rma.nil? ? tr : @alpha * tr + (1 - @alpha) * rma
        results << rma.round(6)
      end

      results
    end
  end

  # ta.sma() — simple moving average
  class SMA
    def self.calculate(values, length)
      results = []
      values.each_with_index do |_, i|
        if i < length - 1
          results << nil
        else
          results << values[(i - length + 1)..i].sum / length.to_f
        end
      end
      results
    end
  end
end