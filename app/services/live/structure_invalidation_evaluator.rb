# frozen_string_literal: true

module Live
  # Shared dual-condition evaluation for structure invalidation.
  # Used by both the sub-second path (UnifiedExitChecker) and
  # the 5-second enforcement path (RiskManagerService::ExitEnforcement).
  module StructureInvalidationEvaluator
    # Checks whether BOTH conditions are met:
    # 1) Underlying moved against trade direction by >= underlying_move_pct
    # 2) Premium dropped from peak by >= premium_drop_pct
    #
    # @param tracker [PositionTracker] position with meta containing direction, entry_underlying_price, peak_premium
    # @param underlying_ltp [Float] current underlying price
    # @param current_premium [Float] current option premium (LTP)
    # @param si_cfg [Hash] structure invalidation config with :underlying_move_pct and :premium_drop_pct
    # @return [Boolean]
    def dual_condition_met?(tracker, underlying_ltp, current_premium, si_cfg)
      entry_underlying = tracker.meta&.dig('entry_underlying_price').to_f
      return false unless entry_underlying.positive?

      direction = tracker.meta&.dig('direction').to_s
      move_pct = si_cfg[:underlying_move_pct].to_f
      return false unless move_pct.positive?

      underlying_moved = case direction
                         when 'long_ce'
                           (entry_underlying - underlying_ltp) / entry_underlying >= move_pct
                         when 'long_pe'
                           (underlying_ltp - entry_underlying) / entry_underlying >= move_pct
                         else
                           false
                         end
      return false unless underlying_moved

      peak_premium = tracker.meta&.dig('peak_premium').to_f
      return false unless peak_premium.positive?
      return false unless current_premium.to_f.positive?

      drop_pct = si_cfg[:premium_drop_pct].to_f
      return false unless drop_pct.positive?

      premium_drop = (peak_premium - current_premium.to_f) / peak_premium
      premium_drop >= drop_pct
    end
  end
end
