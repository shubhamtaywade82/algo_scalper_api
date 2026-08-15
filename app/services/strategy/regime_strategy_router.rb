# frozen_string_literal: true

module Strategy
  # TREND  → Options Buying (existing system, UNCHANGED)
  # CHOP   → Options Selling (new)
  # TRANSITIONING → No entry
  #
  class RegimeStrategyRouter
    REGIME_STRATEGY = {
      trend: :buying,
      trending: :buying,
      trending_phase: :buying,
      chop: :selling,
      ranging: :selling,
      range_bound: :selling,
      transitioning: :none,
    }.freeze

    def self.route(regime:, signal:, index_cfg:)
      strategy = REGIME_STRATEGY[regime.to_s.downcase.to_sym] || :none

      case strategy
      when :buying
        # EXISTING PATH — completely unchanged
        Entries::EntryGuard.try_enter(
          index_cfg: index_cfg,
          pick: signal.pick,
          direction: signal.direction,
        )

      when :selling
        # NEW PATH — options selling
        Strategy::SellingEntry.execute!(
          index_cfg: index_cfg,
          signal: signal,
        )

      when :none
        Rails.logger.info("[RegimeStrategyRouter] No entry in transitioning regime")
        nil
      end
    end
  end
end
