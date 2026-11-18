# frozen_string_literal: true

module Options
  module IndexRules
    # Index-specific rules for BANKNIFTY
    class Banknifty < Base
      INDEX_KEY = 'BANKNIFTY'
      STRIKE_STEP = 100
      MIN_VOLUME = 50_000
      MIN_PREMIUM = 40.0
      MAX_SPREAD_PCT = 0.005 # 0.5%
      ATM_DELTA = 0.45
      OTHER_STRIKE_DELTA = 0.38
      MOVE_THRESHOLD_POINTS = { execution_only: 12.0, scale_ready: 20.0, full_deploy: 28.0 }.freeze
    end
  end
end
