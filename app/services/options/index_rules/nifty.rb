# frozen_string_literal: true

module Options
  module IndexRules
    # Index-specific rules for NIFTY
    class Nifty < Base
      INDEX_KEY = 'NIFTY'
      STRIKE_STEP = 50
      MIN_VOLUME = 30_000
      MIN_PREMIUM = 25.0
      MAX_SPREAD_PCT = 0.003 # 0.3%
      ATM_DELTA = 0.48
      OTHER_STRIKE_DELTA = 0.40
      MOVE_THRESHOLD_POINTS = { execution_only: 4.0, scale_ready: 8.0, full_deploy: 12.0 }.freeze

      def candidate_strikes(atm_strike, _strength = nil)
        [atm_strike, atm_strike + STRIKE_STEP]
      end

      private

      # NIFTY quotes can carry last_price instead of ltp; the other indices never did.
      def premium_of(candidate)
        (candidate[:ltp] || candidate['ltp'] || candidate[:last_price] || 0).to_f
      end
    end
  end
end
