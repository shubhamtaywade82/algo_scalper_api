# frozen_string_literal: true

module Entries
  # Runs entry request through a chain of guards. First guard that blocks wins.
  class EntryGuardPipeline
    PASS = :pass

    def initialize(handlers = default_handlers)
      @handlers = handlers
    end

    # @param context [Hash] Mutable context (index_cfg, pick, direction, etc.)
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
        Guards::DrawdownGuard,
        Guards::EntryPolicyGuard,
        Guards::CircuitBreakerGuard,
        Guards::VixGateGuard,
        Guards::IvVolGateGuard,
        Guards::OptionVolumeVelocityGuard,
        Guards::EarliestEntryGuard,
        Guards::TradingTimeRestrictionGuard,
        Guards::EdgeFailureGuard,
        Guards::LossStreakGuard,
        Guards::DailyLimitsGuard,
        Guards::IndexTradeLimitGuard,
        Guards::MaxConcurrentGuard,
        Guards::InstrumentLookupGuard,
        Guards::LtpResolutionGuard,
        Guards::ExpiryWeekPowerTrendGuard,
        Guards::TimeRegimeGuard,
        Guards::SegmentExpectancyGuard,
        Guards::MiddayQualityGuard,
        Guards::BankniftyLastWeekGuard,
        Guards::ChopScoreGuard,
        Guards::DteEntryWindowGuard,
        Guards::WeeklyExpiryGuard,
        Guards::BosStructureGuard,
        Guards::ExposureGuard,
        Guards::CooldownGuard,
        Guards::SizingGuard,
        Guards::BreakoutReadyGuard,
        Guards::RiskPolicyGuard,
        Guards::SmcNavigatorGuard
      ]
    end
  end
end
