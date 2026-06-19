# frozen_string_literal: true

module Live
  class RiskManagerService
    module ExitEnforcement
      # True once an exit has been requested/sent or finalized for this tracker.
      def exit_in_flight?(tracker)
        tracker.exit_requested_at.present? || tracker.exit_sent_at.present? || tracker.exited?
      end

      # Legacy fallback method for spec compatibility
      def enforce_trailing_stops(exit_engine:)
        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          position_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
          next unless position_data

          pnl_pct = position_data.pnl_pct.to_f

          # Breakeven Lock Logic
          risk_cfg = AlgoConfig.fetch[:risk] || {}
          breakeven_pct = (risk_cfg[:breakeven_after_gain] || 0.35).to_f
          if pnl_pct >= breakeven_pct && !tracker.breakeven_locked?
            tracker.lock_breakeven!
          end

          # Trailing stop activation threshold
          t_config = Positions::TrailingConfig.from_tracker(tracker)
          activation_pct = t_config.direct_trailing_activation_profit_pct.to_f
          next if pnl_pct < activation_pct

          # Peak drawdown check using TrailingConfig
          peak_pct = position_data.peak_profit_pct.to_f
          if Positions::TrailingConfig.peak_drawdown_triggered?(peak_pct, pnl_pct)
            reason = "peak_drawdown_exit (peak: #{peak_pct}, current: #{pnl_pct})"
            dispatch_exit(exit_engine, tracker, reason)
          end
        end
      end

      # Legacy fallback method for spec compatibility
      def enforce_early_trend_failure(exit_engine:)
        nil
      end

      def enforce_premium_r_stop(exit_engine:)
        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_premium_r_stop_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_premium_r_stop_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        ltp = position_data.current_ltp
        return unless ltp

        premium_stop = (pending_meta || tracker.meta || {})['premium_stop_price']
        return unless premium_stop

        return unless ltp.to_f <= premium_stop.to_f

        reason = "PREMIUM_R_STOP (ltp: #{ltp}, stop: #{premium_stop})"
        exit_path = 'premium_r_stop'
        Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
        track_exit_path(tracker, exit_path, reason)
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_premium_r_stop_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def enforce_eod_force_close(exit_engine:, position_data: nil)
        risk = risk_config
        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return unless market_close_time

        now = Time.current
        return unless now >= market_close_time

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          next if tracker.exit_requested_at.present? || tracker.exit_sent_at.present?
          next if carry_held?(tracker)

          reason = "MARKET_CLOSE (EOD #{market_close_time.strftime('%H:%M')} IST)"
          exit_path = 'eod_force_close'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_eod_force_close error: #{e.class} - #{e.message}")
      end

      def carry_held?(tracker)
        OptionsBuying::CarryPolicy.carry_still_valid?(tracker)
      rescue StandardError
        false
      end
    end
  end
end
