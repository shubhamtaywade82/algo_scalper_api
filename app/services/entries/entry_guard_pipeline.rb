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

        return normalize_rejection(result)
      end
      PASS
    end

    private

    def normalize_rejection(result)
      return result if result.is_a?(DecisionRejection)

      if result.is_a?(Hash) && result[:blocked]
        code = result[:blocked].to_s.parameterize.underscore.to_sym
        DecisionRejection.new(code: code, category: :risk, message: result[:blocked].to_s, details: result)
      else
        DecisionRejection.new(code: :guard_blocked, category: :risk, details: { raw: result })
      end
    end

    def default_handlers
      [
        Guards::DrawdownGuard,
        Guards::EntryPolicyGuard,
        Guards::CircuitBreakerGuard,
        Guards::FeedHealthGuard, # blocks on stale/never-synced ticks, positions, or funds feed
        Guards::EdgeFailureGuard,
        Guards::LossStreakGuard,
        Guards::DailyLimitsGuard,
        Guards::MaxConcurrentGuard,
        Guards::GlobalMaxConcurrentGuard,     # portfolio-wide cap across all indices, cheap so runs early
        Guards::StrikeCooldownGuard,          # blocks re-entry of the same contract within its cooldown window
        Guards::InstrumentLookupGuard, # sets context[:instrument] — required by EPT guard
        Guards::ChopScoreGuard, # blocks noisy entries when ADX/Supertrend/BB say chop
        Guards::DirectionConflictGuard, # runs only after regime is chop-cleared; kills a losing opposite-side position, leaves a green one alone
        Guards::SellingIvRankGuard, # selling-only: don't sell premium when IV is cheap
        Guards::MarginLimitGuard,   # selling-only: fail fast if even 1 lot won't fit the margin budget
        Guards::LtpResolutionGuard,
        Guards::ExpiryWeekPowerTrendGuard,   # enriches context[:expiry_power_trend] when pattern detected
        Guards::TimeRegimeGuard,             # reads context[:expiry_power_trend] to bypass S3/S4 block
        Guards::MiddayQualityGuard,          # ADX >= 28 bypass covers all power-trend cases
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
