# frozen_string_literal: true

module Risk
  module Rules
    # Trailing Stop Rule — Spot-Anchored HWM
    #
    # Three-layer exit logic:
    #
    # Layer 1 (Spot Trend Alive):
    #   Hold unconditionally as long as the underlying spot trend is intact
    #   (Supertrend direction matches position, ADX >= min_adx_to_hold, no CHOCH).
    #   Only the hard_floor_pct safety net applies.
    #
    # Layer 2 (Hard Floor):
    #   Exit if option premium falls below entry_price × (1 - hard_floor_pct).
    #   Default: 50% below entry. Prevents catastrophic loss even when trend is alive.
    #
    # Layer 3 (Spot Broken):
    #   Spot trend has broken. Delegate to existing UnifiedExitChecker trailing
    #   logic with severity-aware tightening multiplier.
    class TrailingStopRule < BaseRule
      include Live::SpotTrendEvaluator

      PRIORITY = 50

      def evaluate(context)
        return skip_result unless context.active?

        tracker  = context.tracker
        snapshot = context.tracker_snapshot
        pnl_pct  = snapshot[:pnl_pct].to_f

        # Only engage once trailing is armed (positive PnL)
        return no_action_result unless pnl_pct.positive?

        spot_ctx = evaluate_spot_trend_for(tracker)

        if spot_ctx[:trend_alive]
          # Layer 1: Trend intact — only apply hard floor safety net
          return check_hard_floor(tracker, snapshot)
        end

        # Layer 3: Spot trend broken — evaluate with UEC trailing + severity tightening
        tightening = severity_multiplier(spot_ctx[:severity])

        underlying_ctx = Live::UnifiedExitChecker.send(
          :evaluate_underlying_context, tracker, snapshot
        )

        if underlying_ctx[:action] == :exit
          return exit_result(
            reason: underlying_ctx[:reason],
            metadata: {
              path: 'underlying_context_exit',
              spot_severity: spot_ctx[:severity],
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        combined_multiplier = [tightening * underlying_ctx[:multiplier], 0.3].max

        if Live::UnifiedExitChecker.send(:trailing_stop_hit?, tracker, snapshot,
                                         tightening_multiplier: combined_multiplier)
          return exit_result(
            reason: 'TRAILING_SPOT_BREAK',
            metadata: {
              path: 'trailing_spot_break',
              spot_severity: spot_ctx[:severity],
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      end

      private

      def check_hard_floor(tracker, snapshot)
        entry_price = tracker.entry_price.to_f
        return no_action_result if entry_price.zero?

        floor_pct   = hard_floor_pct
        hard_floor  = entry_price * (1.0 - floor_pct)
        current_ltp = snapshot[:ltp].to_f

        return no_action_result if current_ltp >= hard_floor

        exit_result(
          reason: 'TRAILING_HARD_FLOOR',
          metadata: {
            path: 'trailing_hard_floor',
            entry_price: entry_price,
            current_ltp: current_ltp,
            hard_floor: hard_floor.round(2),
            floor_pct: (floor_pct * 100).round(1)
          }
        )
      end

      def hard_floor_pct
        AlgoConfig.fetch.dig(:risk, :exits, :trailing, :spot_anchored, :hard_floor_pct).to_f
      rescue StandardError
        0.50
      end

      def severity_multiplier(severity)
        case severity
        when :severe   then 0.50
        when :moderate then 0.65
        when :mild     then 0.80
        else                1.00
        end
      end
    end
  end
end
