module BacktestEngine
  module Data
    class CandleNormalizer
      def self.normalize(raw)
        return [] unless raw.is_a?(Array)

        raw.map { |item| BacktestEngine::Market::Candle.from_hash(item) }
      end
    end
  end
end


