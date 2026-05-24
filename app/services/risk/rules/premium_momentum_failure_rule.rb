# frozen_string_literal: true

module Risk
  module Rules
    # Premium Momentum Failure Rule - CRITICAL EXIT for intraday options buying
    #
    # Exits dead option trades before theta eats them. Two gates (in addition to
    # the existing UEC check) prevent false exits on consolidation:
    #
    # Gate 1 — Loss floor: Only fires at -5% or deeper loss.
    #   Rationale: At -1% to -4%, the trade is near breakeven; premium stalling
    #   here is normal consolidation. Don't exit a trade that hasn't lost much yet.
    #
    # Gate 2 — Spot confirmation: Only fires when the underlying spot trend has also
    #   broken (Supertrend flipped OR ADX collapsed below 15 OR CHOCH detected).
    #   Rationale: Premium can stall for 2-3 minutes while the underlying consolidates.
    #   If NIFTY/SENSEX is still trending in the right direction, the option is
    #   likely to resume its move.
    #
    # Priority: 30 (checked after structure invalidation)
    class PremiumMomentumFailureRule < BaseRule
      include Live::SpotTrendEvaluator
      include SessionDetector

      PRIORITY = 30
      DEFAULT_STALL_MINUTES = 3
      MIN_LOSS_PCT_TO_FIRE  = -0.05 # Must be at -5% or worse

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        # Gate 1: Loss must be at least -5% — don't exit near-breakeven trades
        pnl_pct = context.pnl_pct.to_f
        return no_action_result if pnl_pct > MIN_LOSS_PCT_TO_FIRE

        # Gate 2: Spot trend must confirm the failure (only if instrument data available)
        return no_action_result if spot_trend_still_alive?(context.tracker)

        # Both gates passed — delegate to existing UEC check for stall time logic
        if Live::UnifiedExitChecker.premium_momentum_failure_hit?(context.tracker, context.tracker_snapshot)
          return exit_result(
            reason: 'PREMIUM_MOMENTUM_FAILURE',
            metadata: {
              path: 'premium_momentum_failure',
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PremiumMomentumFailureRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      def enabled?(_context = nil)
        pmf_cfg = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}
        pmf_cfg[:enabled] == true
      end

      private

      def spot_trend_still_alive?(tracker)
        # Only gate on spot if we have actual instrument data
        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument # No data = don't block the exit

        spot_ctx = evaluate_spot_trend_for(tracker)
        spot_ctx[:trend_alive]
      rescue StandardError
        false # On error, don't block PMF
      end
    end
  end
end
