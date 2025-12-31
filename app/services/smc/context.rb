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

    def to_h
      {
        structure: structure.to_h,
        liquidity: liquidity.to_h,
        order_blocks: order_blocks.to_h,
        fvg: fvg.to_h,
        premium_discount: pd.to_h
      }
    end
  end
end

