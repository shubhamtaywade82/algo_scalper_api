# frozen_string_literal: true

module Risk
  module Rules
    # Time Stop Rule - EARLY, CONTEXTUAL EXIT for intraday options buying
    #
    # PURPOSE: Prevent holding dead trades - exit regardless of PnL when time limit exceeded
    #
    # This is critical for options because:
    # - Theta decay accelerates with time
    # - Dead premiums don't recover
    # - Time stops prevent "hope trades"
    #
    # Rules:
    # - Scalps: max 15 minutes OR 15 candles
    # - Trend trades:
    #   - NIFTY: max 45 minutes
    #   - SENSEX: max 90 minutes
    #
    # Exit regardless of PnL when time exceeded.
    #
    # Priority: 40 (checked after premium momentum failure)
    class TimeStopRule < BaseRule
      PRIORITY = 40

      # Default time limits (used as fallback if config is missing)
      DEFAULT_TIME_LIMITS = {
        scalp: {
          max_minutes: 15,
          max_candles: 15
        },
        trend: {
          'NIFTY' => 45,      # minutes
          'BANKNIFTY' => 45,  # minutes
          'SENSEX' => 90      # minutes
        }
      }.freeze

      # The underlying intraday_ohlc call is expensive and this rule runs every
      # cycle for every active scalp — throttle the 1m series to once per minute.
      CANDLE_CHECK_TTL_SECONDS = 60

      class << self
        def candle_series_cache
          @candle_series_cache ||= {}
        end

        def candle_series_cache_mutex
          @candle_series_cache_mutex ||= Mutex.new
        end
      end

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        tracker = context.tracker
        return skip_result unless tracker.created_at

        # Determine trade type (scalp vs trend)
        trade_type = determine_trade_type(tracker)
        time_limit = get_time_limit(tracker, trade_type, time_limits(context))

        return skip_result unless time_limit

        pnl = context.position.pnl.to_f
        pnl_pct = context.pnl_pct.to_f
        index_key = tracker.meta&.dig('index_key') || 'NIFTY'

        # Dynamic time stop tightening if position is negative
        if pnl < 0.0 && time_limit > 5
          time_limit = 5 # Reduce time limit to 5 minutes if negative PnL (Theta protection)
        end

        # Determine time limit and profit threshold
        # For trend trades, we allow longer if it's very profitable (e.g., > 5%)
        # But if it's a laggard (< 5% profit) after the time limit, we exit.
        laggard_threshold_pct = 0.05 # 5%

        # Bypass time stop if the trade is strongly in profit (let winners run)
        # EXCEPT for SENSEX where we are more aggressive with time stops
        if pnl_pct >= laggard_threshold_pct && index_key != 'SENSEX'
          # Rails.logger.debug { "[TimeStopRule] Bypassing time stop for #{tracker.order_no} as it is strongly in profit (#{(pnl_pct * 100).round(2)}%)" }
          return skip_result
        end

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

        # For scalps, also check candle count
        if trade_type == :scalp
          candle_limit = time_limits(context)[:scalp][:max_candles] || DEFAULT_TIME_LIMITS[:scalp][:max_candles]
          if candle_count_exceeded?(tracker, candle_limit)
            reason = "TIME_STOP (scalp exceeded #{candle_limit} candles)"
            return exit_result(reason: reason, metadata: {
              trade_type: :scalp,
              candle_limit: candle_limit
            })
          end
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[TimeStopRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      private

      # Determine trade type from tracker metadata or entry path
      def determine_trade_type(tracker)
        entry_metadata = tracker.meta&.dig('entry_metadata') || {}
        entry_path = entry_metadata['entry_path'] || tracker.meta&.dig('entry_path') || tracker.entry_path
        entry_strategy = tracker.entry_strategy.to_s.downcase

        if entry_path.to_s.include?('scalp') || entry_path.to_s.include?('1m') ||
           entry_strategy.include?('scalp') || entry_strategy.include?('momentum')
          return :scalp
        end

        :trend
      end

      # Get time limits for this trade, from risk config with defaults as fallback
      def time_limits(context)
        cfg = context.risk_config[:time_stop] || context.risk_config.dig(:exits, :time_stop) || {}
        trend_cfg = (cfg[:trend] || {}).transform_keys(&:to_s)

        {
          scalp: {
            max_minutes: (cfg.dig(:scalp, :max_minutes) || DEFAULT_TIME_LIMITS[:scalp][:max_minutes]).to_f,
            max_candles: (cfg.dig(:scalp, :max_candles) || DEFAULT_TIME_LIMITS[:scalp][:max_candles]).to_i
          },
          trend: DEFAULT_TIME_LIMITS[:trend].merge(trend_cfg)
        }
      end

      # Get time limit for this trade
      def get_time_limit(tracker, trade_type, limits)
        if trade_type == :scalp
          return limits[:scalp][:max_minutes]
        end

        # Trend trade: get index-specific limit
        index_key = tracker.meta&.dig('index_key') || 'NIFTY'
        limits[:trend][index_key] || limits[:trend]['NIFTY']
      end

      # Check if candle count exceeded (for scalps)
      def candle_count_exceeded?(tracker, max_candles)
        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument

        # Get 1m series to count candles since entry
        series_1m = self.class.candle_series_cache_mutex.synchronize do
          now = Time.current
          entry = self.class.candle_series_cache[instrument.id]
          if entry && entry[:expires_at] > now
            entry[:series]
          else
            series = instrument.candle_series(interval: '1')
            self.class.candle_series_cache[instrument.id] = { series: series, expires_at: now + CANDLE_CHECK_TTL_SECONDS }
            series
          end
        end
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
