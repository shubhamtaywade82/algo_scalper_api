module BacktestEngine
  module Market
    class HtfBiasMapper
      def initialize(htf_candles, htf_structure)
        @htf_candles = htf_candles
        @htf_structure = htf_structure
      end

      def bias_for(timestamp)
        return nil unless timestamp

        index = index_for(timestamp)
        return nil unless index

        @htf_structure[index - 2] # align with CandleSeries.structure offset
      end

      private

      def index_for(timestamp)
        @htf_candles.each_with_index do |candle, index|
          ts = candle[:timestamp]
          return index if ts == timestamp || ts == timestamp.to_i
        end
        nil
      end
    end
  end
end

