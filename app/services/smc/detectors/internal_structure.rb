# frozen_string_literal: true

module Smc
  module Detectors
    # Internal Structure: Lower timeframe intent
    # Uses shorter lookback (1-3 candles) to detect recent structure changes
    # This represents immediate market intent, not higher timeframe control
    class InternalStructure < Structure
      # Internal structure uses shorter lookback (1-3 candles)
      # This detects recent, immediate structure changes
      INTERNAL_LOOKBACK = 2

      def initialize(series, lookback: INTERNAL_LOOKBACK)
        super(series, lookback: lookback)
      end

      def to_h
        super.merge(type: :internal)
      end
    end
  end
end

