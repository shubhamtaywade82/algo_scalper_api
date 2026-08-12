# frozen_string_literal: true

module Entries
  module Guards
    # Blocks a new entry when an opposite-side position is already open on
    # the same index. Without this, a PE trend exhausting into chop and a
    # fresh CE signal firing stack a losing PE against a winning CE
    # simultaneously — the single largest observed leak in session forensics
    # (₹19,767 across two occurrences on 2026-08-12).
    #
    # Deliberately blocks the new entry rather than force-closing the open
    # position — no forced realization of an in-progress trade's PnL.
    class DirectionConflictGuard
      class << self
        include BaseGuard

        def call(context)
          index_key = context.dig(:index_cfg, :key).to_s
          return PASS if index_key.blank?

          new_side = side_for(context[:direction])
          return PASS unless position_scope.where(index_key: index_key).where.not(side: new_side).exists?

          { blocked: "direction conflict: opposite-side position open on #{index_key}" }
        end

        private

        def side_for(direction)
          %i[bullish long].include?(direction.to_s.downcase.to_sym) ? 'long_ce' : 'long_pe'
        end

        def position_scope
          paper_trading_mode? ? PositionTracker.paper.active : PositionTracker.live.active
        end

        def paper_trading_mode?
          AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
        rescue StandardError
          false
        end
      end
    end
  end
end
