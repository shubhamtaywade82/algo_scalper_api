# frozen_string_literal: true

module BacktestEngine
  module Market
    class HtfStructureHelper
      def initialize(htf_candles)
        @series = CandleSeries.new(
          htf_candles.map do |c|
            Candle.new(
              timestamp: c[:timestamp],
              open: c[:open],
              high: c[:high],
              low: c[:low],
              close: c[:close],
              volume: c[:volume]
            )
          end
        )
      end

      delegate :structure, to: :@series
    end
  end
end

