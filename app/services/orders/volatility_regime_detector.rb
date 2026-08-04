# frozen_string_literal: true

module Orders
  class VolatilityRegimeDetector
    def initialize(prices:)
      @prices = Array(prices).map(&:to_f)
    end

    def regime
      return :normal if @prices.size < 5

      returns = @prices.each_cons(2).map { |a, b| (b - a) / a }
      vol = stddev(returns)

      # Thresholds for option premium volatility
      return :low if vol < 0.015
      return :high if vol > 0.035

      :normal
    end

    private

    def stddev(arr)
      return 0.0 if arr.empty?

      mean = arr.sum / arr.size.to_f
      variance = arr.sum { |x| (x - mean)**2 } / arr.size.to_f
      Math.sqrt(variance)
    end
  end
end
