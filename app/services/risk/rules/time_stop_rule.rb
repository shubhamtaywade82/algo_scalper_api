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
        return skip_result unless tracker.created_at

        # Determine trade type (scalp vs trend)
        trade_type = determine_trade_type(tracker)
        time_limit = get_time_limit(tracker, trade_type)

        return skip_result unless time_limit

        time_limit = apply_regime_decay_factor(time_limit)

        pnl_pct = context.pnl_pct.to_f

        # Any profitable or breakeven position is immune — trailing system owns winners.
        return skip_result if pnl_pct >= 0.0

        # Spot trend still intact? Give the trade more time regardless of PnL.
        return skip_result if spot_trend_alive?(tracker)

        # Check if time limit exceeded
        entry_time = tracker.created_at
        elapsed_minutes = ((Time.current - entry_time) / 60.0).round(2)

        if elapsed_minutes >= time_limit
          status = pnl_pct.positive? ? 'laggard' : 'loss'
          reason = "TIME_STOP (#{trade_type} #{status} trade exceeded #{time_limit} minutes, elapsed: #{elapsed_minutes} min, pnl: #{(pnl_pct * 100).round(2)}%)"
          return exit_result(reason: reason, metadata: {
            trade_type: trade_type,
            time_limit: time_limit,
            elapsed_minutes: elapsed_minutes,
            pnl_pct: pnl_pct
          })
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

        # Trend trade: get index-specific limit
        index_key = tracker.meta&.dig('index_key') || 'NIFTY'
        limits[:trend][index_key] || limits[:trend]['NIFTY']
      end

      # Theta burn is convex — it accelerates hardest in the Chop/Theta zone (S3) and
      # the Close/Gamma zone (S4). A flat time limit lets a "dead trade" opened at
      # 13:50 ride the same 20 minutes as one opened at 10:00, even though the second
      # half of that window is far more destructive to premium. Shrink the limit in
      # those decay-dominant regimes so dead trades get cut sooner when it matters most.
      def apply_regime_decay_factor(time_limit)
        regime_service = Live::TimeRegimeService.instance
        regime = regime_service.current_regime

        factor = case regime
                 when Live::TimeRegimeService::CHOP_DECAY then chop_decay_time_factor
                 when Live::TimeRegimeService::CLOSE_GAMMA then close_gamma_time_factor
                 else 1.0
                 end

        return time_limit if factor >= 1.0

        [(time_limit * factor), minimum_time_limit_minutes].max.round(2)
      rescue StandardError
        time_limit
      end

      def chop_decay_time_factor
        regime_decay_cfg.fetch(:chop_decay_factor, 0.6).to_f
      end

      def close_gamma_time_factor
        regime_decay_cfg.fetch(:close_gamma_factor, 0.5).to_f
      end

      def minimum_time_limit_minutes
        regime_decay_cfg.fetch(:minimum_minutes, 5).to_f
      end

      def regime_decay_cfg
        AlgoConfig.fetch.dig(:risk, :time_stop, :regime_decay) || {}
      rescue StandardError
        {}
      end

      def spot_trend_alive?(tracker)
        # Only bypass if we have actual instrument data — don't bypass on missing data
        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument

        result = evaluate_spot_trend_for(tracker)
        result[:trend_alive]
      rescue StandardError
        false # On error, don't block the time stop
      end

      # Check if candle count exceeded (for scalps)
      def candle_count_exceeded?(tracker, max_candles)
        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument

        # Get 1m series to count candles since entry
        series_1m = instrument.candle_series(interval: '1')
        return false unless series_1m&.candles&.any?

        entry_time = tracker.created_at
        return false unless entry_time

        # Count candles after entry time
        candles_after_entry = series_1m.candles.select { |c| c.timestamp >= entry_time }
        candles_after_entry.size > max_candles
      rescue StandardError => e
        Rails.logger.error("[TimeStopRule] candle_count_exceeded? error: #{e.class} - #{e.message}")
        false
      end
    end
  end
end
