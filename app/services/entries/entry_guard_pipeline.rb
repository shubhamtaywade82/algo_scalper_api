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
        Guards::DrawdownGuard,
        Guards::EntryPolicyGuard,
        Guards::CircuitBreakerGuard,
        Guards::VixGateGuard,
        Guards::EarliestEntryGuard,
        Guards::MiddayQualityGuard,          # ADX >= 28 bypass covers all power-trend cases
        Guards::EdgeFailureGuard,
        Guards::LossStreakGuard,
        Guards::SegmentExpectancyGuard,
        Guards::StrikeCooldownGuard,
        Guards::DailyLimitsGuard,
        Guards::MaxConcurrentGuard,
        Guards::InstrumentLookupGuard,       # sets context[:instrument] — required by EPT guard
        Guards::CompressionSetupGuard,       # positional+carry: require ATR compression setup
        Guards::LtpResolutionGuard,
        Guards::BidAskSpreadGuard,
        Guards::TransactionCostGuard,        # pre-trade TCM: block when fees+spread+slippage > expected edge
        Guards::BreakoutReadyGuard,          # intraday: 1m breakout + OI unwind armed
        Guards::RsiBiasGuard,
        Guards::ExpiryWeekPowerTrendGuard,   # enriches context[:expiry_power_trend] when pattern detected
        Guards::TimeRegimeGuard,             # reads context[:expiry_power_trend] to bypass S3/S4 block
        Guards::DteEntryWindowGuard,
        Guards::BankniftyLastWeekGuard,
        Guards::WeeklyExpiryGuard,
        Guards::BosStructureGuard,
        Guards::ExposureGuard,
        Guards::CooldownGuard,
        Guards::SizingGuard,
        Guards::RiskPolicyGuard,
        Guards::SmcNavigatorGuard
      ]
    end
  end
end
