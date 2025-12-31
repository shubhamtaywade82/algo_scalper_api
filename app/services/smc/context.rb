# frozen_string_literal: true

module Smc
  class Context
    attr_reader :structure, :liquidity, :order_blocks, :fvg, :pd

    def initialize(series)
      @structure = Detectors::Structure.new(series)
      @liquidity = Detectors::Liquidity.new(series)
      @order_blocks = Detectors::OrderBlocks.new(series)
      @fvg = Detectors::Fvg.new(series)
      @pd = Detectors::PremiumDiscount.new(series)
    end
  end
end

