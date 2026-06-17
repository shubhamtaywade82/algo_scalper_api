# frozen_string_literal: true

module Risk
  module Rules
    # Stateless profit-floor enforcement on the tick path (UnifiedExitChecker).
    # Arms when HWM crosses a rupee threshold, then exits on give-back below trail % of HWM.
    class ProfitFloorExitRule < BaseRule
      PRIORITY = 28

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        cfg = rule_config
        hwm_rupees = hwm_rupees_for(context).to_f
        net_pnl = context.pnl_rupees.to_f
        return no_action_result unless hwm_rupees.positive?

        arm_threshold = arm_threshold_rupees(context, cfg)
        return no_action_result unless arm_threshold.positive?
        return no_action_result unless hwm_rupees >= arm_threshold

        trail_pct = cfg[:trail_pct].to_f
        trail_pct = 0.72 if trail_pct <= 0

        floor = [(hwm_rupees * trail_pct).ceil, arm_threshold].max
        return no_action_result unless net_pnl <= floor

        exit_result(
          reason: "PROFIT_FLOOR_TICK (hwm: ₹#{hwm_rupees.round(2)}, floor: ₹#{floor}, now: ₹#{net_pnl.round(2)})",
          metadata: {
            path: 'profit_floor_tick',
            hwm_rupees: hwm_rupees,
            floor_rupees: floor,
            net_pnl: net_pnl,
            arm_threshold: arm_threshold,
            trail_pct: trail_pct
          }
        )
      end

      def enabled?(_context = nil)
        rule_config[:enabled] == true
      end

      private

      def rule_config
        AlgoConfig.fetch.dig(:risk, :profit_floor) || {}
      rescue StandardError
        {}
      end

      def arm_threshold_rupees(context, cfg)
        min_arm = cfg[:min_arm_rupees].to_f
        lock_pct = cfg[:lock_pct]
        capital = capital_deployed(context)

        pct_arm = if lock_pct && capital.positive?
                    (capital * lock_pct.to_f).ceil
                  end

        candidates = [min_arm, pct_arm].compact.select(&:positive?)
        return 0.0 if candidates.empty?

        candidates.min
      end

      def capital_deployed(context)
        snapshot = context.tracker_snapshot
        if snapshot.is_a?(Hash) && snapshot[:capital_deployed]
          return snapshot[:capital_deployed].to_f
        end

        entry = context.entry_price.to_f
        qty = context.quantity.to_i
        return 0.0 unless entry.positive? && qty.positive?

        entry * qty
      end

      def hwm_rupees_for(context)
        snapshot = context.tracker_snapshot
        return snapshot[:hwm_pnl] if snapshot.is_a?(Hash) && snapshot[:hwm_pnl]

        context.high_water_mark || context.tracker&.high_water_mark_pnl
      end
    end
  end
end
