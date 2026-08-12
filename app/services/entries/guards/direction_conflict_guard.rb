# frozen_string_literal: true

module Entries
  module Guards
    # Runs after ChopScoreGuard, so any signal reaching here has already
    # cleared the chop filter — the opposite signal is regime-confirmed,
    # not chop whipsaw.
    #
    # Force-closes an opposite-side position on the same index only if it's
    # already net-negative. A green position is left alone to run its own
    # SL/trail — this only cuts a leg that's already wrong and bleeding
    # theta against a confirmed reversal (₹19,767 leak on 2026-08-12, where
    # held PE legs kept losing while a fresh CE trend was already winning).
    class DirectionConflictGuard
      class << self
        include BaseGuard

        REASON = 'DIRECTION_CONFLICT_KILL'

        def call(context)
          index_key = context.dig(:index_cfg, :key).to_s
          return PASS if index_key.blank?

          new_side = side_for(context[:direction])
          position_scope.where(index_key: index_key).where.not(side: new_side).find_each do |tracker|
            kill_if_losing(tracker, new_side)
          end

          PASS
        end

        private

        def side_for(direction)
          %i[bullish long].include?(direction.to_s.downcase.to_sym) ? 'long_ce' : 'long_pe'
        end

        def kill_if_losing(tracker, new_side)
          pnl = tracker.current_pnl_rupees.to_f
          return if pnl >= 0

          Rails.logger.warn(
            "[DirectionConflictGuard] closing #{tracker.side} #{tracker.symbol} " \
            "(pnl=#{pnl.round(2)}) before entering #{new_side} on #{tracker.index_key}"
          )
          force_close!(tracker)
        end

        def force_close!(tracker)
          engine = nil
          router = TradingSystem::OrderRouter.new
          engine = Live::ExitEngine.new(order_router: router)
          engine.start
          engine.execute_exit(tracker, REASON)
        rescue StandardError => e
          Rails.logger.error("[DirectionConflictGuard] force-close failed for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        ensure
          engine&.stop
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
