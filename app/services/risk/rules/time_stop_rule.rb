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
    # - Scalps: max 2-3 minutes OR 2 candles
    # - Trend trades:
    #   - NIFTY: max 45 minutes
    #   - SENSEX: max 90 minutes
    #
    # Exit regardless of PnL when time exceeded.
    #
    # Priority: 40 (checked after premium momentum failure)
    class TimeStopRule < BaseRule
      PRIORITY = 40

      # Time limits by trade type and index
      TIME_LIMITS = {
        scalp: {
          max_minutes: 3,
          max_candles: 2
        },
        trend: {
          'NIFTY' => 45,      # minutes
          'BANKNIFTY' => 45,  # minutes
          'SENSEX' => 90      # minutes
        }
      }.freeze

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        tracker = context.tracker
        return skip_result unless tracker.created_at

        # Determine trade type (scalp vs trend)
        trade_type = determine_trade_type(tracker)
        time_limit = get_time_limit(tracker, trade_type)

        return skip_result unless time_limit

        # Check if time limit exceeded
        entry_time = tracker.created_at
        elapsed_minutes = ((Time.current - entry_time) / 60.0).round(2)

        if elapsed_minutes >= time_limit
          reason = "TIME_STOP (#{trade_type} trade exceeded #{time_limit} minutes, elapsed: #{elapsed_minutes} min)"
          return exit_result(reason: reason, metadata: {
            trade_type: trade_type,
            time_limit: time_limit,
            elapsed_minutes: elapsed_minutes
          })
        end

        # For scalps, also check candle count
        if trade_type == :scalp
          candle_limit = TIME_LIMITS[:scalp][:max_candles]
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
        # Check entry metadata for trade type
        entry_metadata = tracker.meta&.dig('entry_metadata') || {}
        entry_path = entry_metadata['entry_path'] || tracker.meta&.dig('entry_path')

        # Scalp indicators: 1m timeframe, quick entries
        if entry_path&.include?('1m') || entry_path&.include?('scalp')
          return :scalp
        end

        # Default to trend for longer timeframes
        :trend
      end

      # Get time limit for this trade
      def get_time_limit(tracker, trade_type)
        if trade_type == :scalp
          return TIME_LIMITS[:scalp][:max_minutes]
        end

        # Trend trade: get index-specific limit
        index_key = tracker.meta&.dig('index_key') || 'NIFTY'
        TIME_LIMITS[:trend][index_key] || TIME_LIMITS[:trend]['NIFTY']
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
