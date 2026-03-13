# frozen_string_literal: true

module Orders
  class GammaDetector
    def initialize(prices:)
      @prices = Array(prices).map(&:to_f)
    end

    def gamma_expanding?
      return false if @prices.size < 3

      v1 = velocity(@prices[-3], @prices[-2])
      v2 = velocity(@prices[-2], @prices[-1])

      # Acceleration > threshold (0.02)
      (v2 - v1) > 0.02
    end

    private

    def velocity(a, b)
      return 0.0 if a.zero?
      (b - a) / a
    end
  end
end
