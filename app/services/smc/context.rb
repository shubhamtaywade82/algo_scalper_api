# frozen_string_literal: true

module Smc
  class Context
    attr_reader :internal_structure, :swing_structure, :liquidity, :order_blocks, :fvg, :pd, :trend

    def initialize(series)
      @internal_structure = Detectors::InternalStructure.new(series)
      @swing_structure = Detectors::SwingStructure.new(series)
      @liquidity = Detectors::Liquidity.new(series)
      @order_blocks = Detectors::OrderBlocks.new(series)
      @fvg = Detectors::Fvg.new(series)
      @pd = Detectors::PremiumDiscount.new(series)
      # Primary trend comes from swing structure (higher TF control)
      @trend = @swing_structure.trend
    end

    # Legacy accessor for backward compatibility
    def structure
      @swing_structure
    end

    def to_h
      {
        internal_structure: internal_structure.to_h,
        swing_structure: swing_structure.to_h,
        # Legacy key for backward compatibility
        structure: swing_structure.to_h,
        liquidity: liquidity.to_h,
        order_blocks: order_blocks.to_h,
        fvg: fvg.to_h,
        premium_discount: pd.to_h,
        trend: trend
      }
    end
  end
end
