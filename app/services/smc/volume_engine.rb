# frozen_string_literal: true

module Smc
  class VolumeEngine
    Result = Struct.new(:spike, :ratio, :avg, :current)

    def initialize(series, lookback: 20, spike_mult: 1.8)
      @series = series
      @lookback = lookback
      @spike_mult = spike_mult
    end

    def call
      bars = @series&.candles || []
      return empty_result if bars.empty?

      vols = bars.last(@lookback).map(&:volume)
      return empty_result if vols.empty?

      avg = vols.sum / vols.size.to_f
      current = bars.last.volume
      ratio = avg.positive? ? current / avg : 0.0

      Result.new(
        spike: ratio >= @spike_mult,
        ratio: ratio,
        avg: avg,
        current: current
      )
    end

    private

    def empty_result
      Result.new(spike: false, ratio: 0.0, avg: 0.0, current: 0)
    end
  end
end
