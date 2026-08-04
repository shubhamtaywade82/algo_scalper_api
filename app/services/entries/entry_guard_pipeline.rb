# frozen_string_literal: true

module Entries
  # Runs entry request through a chain of guards. First guard that blocks wins.
  # Used by EntryGuard.try_enter to make guard order explicit and each step testable.
  class EntryGuardPipeline
    PASS = :pass

    def initialize(handlers = default_handlers)
      @handlers = handlers
    end

    # @param context [Hash] Mutable context (index_cfg, pick, direction, etc.). Handlers may set :instrument, :ltp, :side, :is_supertrend.
    # @return [Symbol] :pass if all handlers passed
    # @return [Hash] { blocked: String } if a handler blocked
    def run(context)
      @handlers.each do |handler|
        result = handler.call(context)
        next if result == PASS

        return result
      end
      PASS
    end

    private

    def default_handlers
      [
        Guards::CircuitBreakerGuard,
        Guards::BosContractGuard,
        Guards::TimeRegimeGuard,
        Guards::BankniftyLastWeekGuard,
        Guards::EdgeFailureGuard,
        Guards::DailyLimitsGuard,
        Guards::InstrumentLookupGuard,
        Guards::ExposureGuard,
        Guards::CooldownGuard,
        Guards::LtpResolutionGuard
      ]
    end
  end
end
