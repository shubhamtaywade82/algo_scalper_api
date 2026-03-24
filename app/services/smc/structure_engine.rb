# frozen_string_literal: true

module Smc
  # Rule-based swing envelope + BOS-style trend (LuxAlgo-style simplification).
  # Works on the canonical {CandleSeries} model (OHLCV only).
  class StructureEngine
    State = Struct.new(
      :trend,
      :last_bos,
      :last_choch,
      :hh, :hl, :lh, :ll
    )

    LOOKBACK = 20

    def initialize(series)
      @series = series
      @state = State.new(trend: :neutral, last_bos: nil, last_choch: nil,
                         hh: nil, hl: nil, lh: nil, ll: nil)
    end

    def call
      detect_structure
      detect_bos_choch
      @state
    end

    private

    def bars
      @series&.candles || []
    end

    def detect_structure
      window = bars.last(LOOKBACK)
      return if window.size < 5

      highs = window.map(&:high)
      lows = window.map(&:low)
      @state.hh = highs.max
      @state.ll = lows.min
    end

    def detect_bos_choch
      last = bars.last
      return unless last && @state.hh && @state.ll

      last_close = last.close
      if last_close > @state.hh
        @state.trend = :bullish
        @state.last_bos = last_close
      elsif last_close < @state.ll
        @state.trend = :bearish
        @state.last_bos = last_close
      end
    end
  end
end
