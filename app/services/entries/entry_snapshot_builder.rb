# frozen_string_literal: true

module Entries
  # Builds pinned config snapshot and entry analytics fields for new positions.
  class EntrySnapshotBuilder
    class << self
      def build(index_cfg:, pick:)
        dte = Trading::DteResolver.days_to_expiry(pick: pick, index_cfg: index_cfg)
        dte_params = Trading::DteParameterResolver.resolve(dte: dte)
        snapshot = pin_snapshot(dte: dte)

        {
          dte_at_entry: dte,
          vix_at_entry: Market::VixGate.current_ltp,
          spread_guard_pct: spread_guard_pct_for(index_cfg),
          atm_strike: pick[:strike] || pick['strike'],
          expiry_date: pick[:expiry_date] || pick['expiry_date'],
          entry_context: dte_params,
          config_snapshot: snapshot
        }
      end

      private

      def pin_snapshot(dte:)
        snapshot = AlgoConfig.position_snapshot.deep_dup
        overrides = Trading::DteParameterResolver.risk_overrides_for(dte: dte)
        return snapshot if overrides.empty?

        snapshot[:risk] = (snapshot[:risk] || {}).deep_merge(overrides)
        snapshot
      end

      def spread_guard_pct_for(index_cfg)
        index_override = index_cfg.dig(:execution, :max_bid_ask_spread_pct)
        return index_override.to_f if index_override

        OptionsBuying::Mode.config.dig(:execution, :max_bid_ask_spread_pct).to_f
      rescue StandardError
        0.015
      end
    end
  end
end
