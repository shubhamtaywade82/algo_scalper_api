# frozen_string_literal: true

module Smc
  module Detectors
    # Swing Structure: Higher timeframe control
    # Uses longer lookback (5-10 candles) to detect significant structure changes
    # This represents higher timeframe bias and major trend shifts
    class SwingStructure < Structure
      # Swing structure uses longer lookback (5-10 candles)
      # This detects significant, higher timeframe structure changes
      SWING_LOOKBACK = 5

      def initialize(series, lookback: SWING_LOOKBACK)
        super
      end

      def to_h
        super.merge(type: :swing)
      end
    end
  end
end
