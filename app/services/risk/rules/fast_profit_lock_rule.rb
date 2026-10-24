# frozen_string_literal: true

module Risk
  module Rules
    # Fast Profit Lock Rule — simulates tiered partial booking via a ratcheting floor
    #
    # PROBLEM: Buying options is a wasting-asset bet. The highest-probability winning
    # pattern is a fast early pop (first few minutes) that can fade just as quickly to
    # theta/IV-crush. The existing exits wait for either a big absolute target (TakeProfitRule
    # @ 25%) or a 15%-profit breakeven tier (trailing_tiers) — both too slow to protect an
    # early win that pops and fades before reaching them.
    #
    # A real options buyer would scale out — sell half the lot at the first solid pop,
    # let the rest run. This bot's exits are full-position only (see PositionTracker /
    # ExitEngine — single fill, single exit, no partial-quantity support), so true
    # scale-out isn't available without refactoring locked execution/lifecycle plumbing.
    #
    # This rule gets ~equivalent economics without partial fills: once the position's
    # peak profit crosses an early tier threshold, it ratchets a hard profit FLOOR.
    # If price gives back below that floor, the whole position exits — guaranteeing
    # the trade locks in at least the floor's profit once the tier was touched. This
    # mirrors "sold half at the tier, protected the rest with a stop at the floor"
    # in realized-PnL terms, entirely via the existing single-exit path.
    #
    # Tiers are intentionally MUCH earlier/tighter than trailing_tiers (which starts
    # protecting at 3% and reaches breakeven at 15%) — this rule exists specifically
    # to catch the fast-pop-then-fade pattern in the first few percent of profit.
    #
    # Config (config/algo.yml under risk.fast_profit_lock):
    #   fast_profit_lock:
    #     enabled: true
    #     tiers:
    #       - { trigger_pct: 0.05, lock_pct: 0.02 }   # touch +5% → guarantee at least +2%
    #       - { trigger_pct: 0.08, lock_pct: 0.045 }  # touch +8% → guarantee at least +4.5%
    #       - { trigger_pct: 0.12, lock_pct: 0.07 }   # touch +12% → guarantee at least +7%
    #       - { trigger_pct: 0.18, lock_pct: 0.11 }   # touch +18% → guarantee at least +11%
    #
    # Priority: 33 — after TakeProfitRule (30, owns the big-target exit) and
    # PercentagePnlRule (25), before SecureProfitRule (35, the rupee-based ratchet)
    # and TrailingStopRule (50). Only acts once a tier has actually been touched —
    # otherwise it's a no-op and the rest of the stack owns the decision.
    class FastProfitLockRule < BaseRule
      PRIORITY = 33

      DEFAULT_TIERS = [
        { trigger_pct: 0.05, lock_pct: 0.02 },
        { trigger_pct: 0.08, lock_pct: 0.045 },
        { trigger_pct: 0.12, lock_pct: 0.07 },
        { trigger_pct: 0.18, lock_pct: 0.11 }
      ].freeze

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        peak_pct = context.peak_profit_pct
        current_pct = context.pnl_pct.to_f
        return no_action_result unless peak_pct

        # Both peak_profit_pct and pnl_pct are stored as decimals (0.12 = 12%, see
        # Positions::ActiveCache#recalculate_pnl) — compare directly against tier configs.
        peak_decimal = peak_pct.to_f

        tier = highest_touched_tier(peak_decimal)
        return no_action_result unless tier

        lock_pct = tier[:lock_pct].to_f
        return no_action_result if current_pct >= lock_pct

        exit_result(
          reason: "FAST_PROFIT_LOCK (touched #{(tier[:trigger_pct] * 100).round(1)}% peak, " \
                  "floor #{(lock_pct * 100).round(1)}%, now #{(current_pct * 100).round(2)}%)",
          metadata: {
            path: 'fast_profit_lock',
            tier_trigger_pct: tier[:trigger_pct],
            tier_lock_pct: lock_pct,
            peak_profit_pct: peak_decimal,
            current_pnl_pct: current_pct
          }
        )
      end

      def enabled?(_context = nil)
        cfg = AlgoConfig.fetch.dig(:risk, :fast_profit_lock) || {}
        cfg.fetch(:enabled, true) != false
      end

      private

      # Returns the most protective (highest-trigger) tier whose threshold the peak
      # has touched, since reaching a higher tier supersedes a lower one's floor.
      def highest_touched_tier(peak_decimal)
        tiers.select { |t| peak_decimal >= t[:trigger_pct].to_f }
             .max_by { |t| t[:trigger_pct].to_f }
      end

      def tiers
        @tiers ||= begin
          configured = AlgoConfig.fetch.dig(:risk, :fast_profit_lock, :tiers)
          raw = configured.is_a?(Array) && configured.any? ? configured : DEFAULT_TIERS
          raw.map { |t| { trigger_pct: t[:trigger_pct].to_f, lock_pct: t[:lock_pct].to_f } }
             .sort_by { |t| t[:trigger_pct] }
        end
      end
    end
  end
end
