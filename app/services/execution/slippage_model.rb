# frozen_string_literal: true

module Execution
  class SlippageModel
    def self.apply(price:, side:)
      slippage = 0.001 # 0.1%

      if side == :buy
        price * (1 + slippage)
      else
        price * (1 - slippage)
      end
    end
  end
end
