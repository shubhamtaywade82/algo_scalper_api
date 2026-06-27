# frozen_string_literal: true

module Entries
  module Guards
    # Blocks new entries during configured avoid_periods (trading_time_restrictions in algo config).
    class TradingTimeRestrictionGuard
      class << self
        include BaseGuard

        def call(_context)
          return PASS unless TradingSession::Service.trading_time_restrictions_enabled?

          ist = TradingSession::Service.current_ist_time
          return PASS unless TradingSession::Service.restricted_time_period?(ist)

          period = TradingSession::Service.find_restricted_period(ist)
          { blocked: "session blackout #{period} (trading_time_restrictions)" }
        rescue StandardError => e
          Rails.logger.warn("[TradingTimeRestrictionGuard] #{e.class} - #{e.message}")
          PASS
        end
      end
    end
  end
end
