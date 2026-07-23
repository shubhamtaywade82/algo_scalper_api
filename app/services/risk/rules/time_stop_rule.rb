# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces a dynamic, DTE-scaled time stop limit on option positions.
    # Scalps use a fixed base of 8 minutes, while trend trades use index-specific base settings
    # scaled by (DTE / 7.0), with a minimum floor to avoid instant closures.
    class TimeStopRule < BaseRule
      PRIORITY = 40

      def evaluate(context)
        return skip_result unless context.active?

        tracker = context.tracker
        elapsed_seconds = context.current_time - tracker.created_at

        # Resolve DTE-scaled time limit
        dte = days_to_expiry(tracker)
        base_limit_minutes = base_time_limit_minutes(context)

        # Scale allowed hold time based on DTE: BaseLimit * (DTE / 7.0)
        scale_factor = dte / 7.0
        allowed_seconds = base_limit_minutes * 60 * scale_factor

        # Apply a minimum floor (e.g., 3 minutes) to avoid instant closures
        floor_seconds = 180.0
        final_allowed_seconds = [allowed_seconds, floor_seconds].max

        if elapsed_seconds >= final_allowed_seconds
          exit_result(
            reason: 'TIME_STOP',
            metadata: {
              path: 'time_stop',
              elapsed_seconds: elapsed_seconds.round(1),
              allowed_seconds: final_allowed_seconds.round(1),
              dte: dte,
              base_limit_minutes: base_limit_minutes
            }
          )
        else
          no_action_result
        end
      end

      def enabled?(context = nil)
        return false unless context

        cfg = context.risk_config[:time_stop] || context.risk_config.dig(:exits, :time_stop)
        cfg&.dig(:enabled) != false
      end

      private

      def days_to_expiry(tracker)
        watchable = tracker.watchable
        return 7 unless watchable.respond_to?(:expiry_date)

        expiry = watchable.expiry_date
        return 7 unless expiry && expiry > Date.new(2000, 1, 1)

        [(expiry - Date.current).to_i, 0].max
      end

      def base_time_limit_minutes(context)
        tracker = context.tracker
        cfg = context.risk_config[:time_stop] || context.risk_config.dig(:exits, :time_stop) || {}

        entry_strategy = tracker.entry_strategy.to_s.downcase
        entry_path = tracker.entry_path.to_s.downcase

        is_scalp = entry_strategy.include?('scalp') ||
                   entry_path.include?('scalp') ||
                   entry_strategy.include?('momentum') ||
                   (context.risk_config.dig(:options_buying, :mode).to_s == 'intraday_scalper')

        if is_scalp
          (cfg.dig(:scalp, :max_minutes) || 8).to_f
        else
          index_key = (tracker.index_key || tracker.underlying_instrument&.symbol_name || 'NIFTY').to_s.upcase
          trend_cfg = cfg[:trend] || {}
          (trend_cfg[index_key] || trend_cfg[index_key.to_sym] || 15).to_f
        end
      end
    end
  end
end
