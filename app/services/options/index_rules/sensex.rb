# frozen_string_literal: true

module Options
  module IndexRules
    # Index-specific rules for SENSEX
    class Sensex < Base
      INDEX_KEY = 'SENSEX'
      STRIKE_STEP = 100
      MIN_VOLUME = 20_000
      MIN_PREMIUM = 30.0
      MAX_SPREAD_PCT = 0.003 # 0.3%
      ATM_DELTA = 0.50
      OTHER_STRIKE_DELTA = 0.42
      # execution_only is always blocked before this is read
      MOVE_THRESHOLD_POINTS = { execution_only: nil, scale_ready: 15.0, full_deploy: 25.0 }.freeze
    end
  end
end
