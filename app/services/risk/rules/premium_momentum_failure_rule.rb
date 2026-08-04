# frozen_string_literal: true

module Risk
  module Rules
    # Premium Momentum Failure Rule - CRITICAL EXIT for intraday options buying
    #
    # PURPOSE: Kill dead option trades before theta eats them
    #
    # This rule replaces:
    # - Early Trend Failure (ETF)
    # - Stall Detection
    # - Most trailing stop logic
    #
    # Logic: Track last premium high (CE) or low (PE)
    # Exit when premium does NOT make progress within N candles
    #
    # This aligns with:
    # - Gamma decay
    # - Theta bleed
    # - Real option premium behavior
    #
    # Index-specific thresholds:
    # - NIFTY: 1m → 2 candles, 5m → 1 candle
    # - SENSEX: 1m → 3 candles, 5m → 2 candles
    #
    # Priority: 30 (checked after structure invalidation)
    class PremiumMomentumFailureRule < BaseRule
      PRIORITY = 30

      # Index-specific momentum failure thresholds
      # Format: { index_key => { timeframe => max_candles_without_progress } }
      MOMENTUM_THRESHOLDS = {
        'NIFTY' => { '1' => 2, '5' => 1 },
        'BANKNIFTY' => { '1' => 2, '5' => 1 },
        'SENSEX' => { '1' => 3, '5' => 2 }
      }.freeze

      DEFAULT_THRESHOLDS = { '1' => 2, '5' => 1 }.freeze

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        tracker = context.tracker
        instrument = tracker.instrument || tracker.watchable&.instrument
        return skip_result unless instrument

        # Get position direction
        position_direction = determine_position_direction(tracker, instrument)
        return skip_result unless position_direction.in?(%i[bullish bearish])

        # Get index key for threshold lookup
        index_key = tracker.meta&.dig('index_key') || instrument&.symbol_name&.split('_')&.first&.upcase || 'NIFTY'
        thresholds = MOMENTUM_THRESHOLDS[index_key] || DEFAULT_THRESHOLDS

        # Check 1m momentum failure
        if momentum_failed?(instrument, position_direction, '1', thresholds['1'])
          reason = "PREMIUM_MOMENTUM_FAILURE (1m: no progress in #{thresholds['1']} candles)"
          return exit_result(reason: reason, metadata: { timeframe: '1m', candles: thresholds['1'] })
        end

        # Check 5m momentum failure
        if momentum_failed?(instrument, position_direction, '5', thresholds['5'])
          reason = "PREMIUM_MOMENTUM_FAILURE (5m: no progress in #{thresholds['5']} candles)"
          return exit_result(reason: reason, metadata: { timeframe: '5m', candles: thresholds['5'] })
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PremiumMomentumFailureRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      private

      # Determine position direction
      def determine_position_direction(tracker, instrument)
        direction = tracker.meta&.dig('direction')&.to_sym
        return direction if direction.in?(%i[bullish bearish])

        symbol = instrument&.symbol_name&.to_s&.upcase
        return :bullish if symbol&.include?('CE')
        return :bearish if symbol&.include?('PE')

        entry_metadata = tracker.meta&.dig('entry_metadata') || {}
        direction = entry_metadata['direction']&.to_sym
        return direction if direction.in?(%i[bullish bearish])

        nil
      end

      # Check if premium momentum has failed
      def momentum_failed?(instrument, position_direction, interval, max_candles)
        series = instrument.candle_series(interval: interval)
        return false unless series&.candles&.any?

        candles = series.candles
        return false if candles.size < max_candles + 1

        # Get recent candles (need at least max_candles + 1 to check progress)
        recent_candles = candles.last(max_candles + 1)
        return false if recent_candles.size < max_candles + 1

        # Track premium high/low based on position direction
        if position_direction == :bullish
          # Bullish (CE): track premium high
          current_premium = recent_candles.last&.close
          previous_high = recent_candles.first(max_candles).map(&:high).max

          return false unless current_premium && previous_high

          # Momentum failed if current premium hasn't exceeded previous high
          # Allow small tolerance (0.1%) for noise
          tolerance = previous_high * 0.001
          momentum_failed = current_premium <= (previous_high + tolerance)

          if momentum_failed
            Rails.logger.debug(
              "[PremiumMomentumFailureRule] Bullish momentum failed on #{interval}m: " \
              "current=#{current_premium.round(2)}, previous_high=#{previous_high.round(2)}"
            )
          end

          momentum_failed
        else
          # Bearish (PE): track premium low
          current_premium = recent_candles.last&.close
          previous_low = recent_candles.first(max_candles).map(&:low).min

          return false unless current_premium && previous_low

          # Momentum failed if current premium hasn't dropped below previous low
          tolerance = previous_low * 0.001
          momentum_failed = current_premium >= (previous_low - tolerance)

          if momentum_failed
            Rails.logger.debug(
              "[PremiumMomentumFailureRule] Bearish momentum failed on #{interval}m: " \
              "current=#{current_premium.round(2)}, previous_low=#{previous_low.round(2)}"
            )
          end

          momentum_failed
        end
      rescue StandardError => e
        Rails.logger.error("[PremiumMomentumFailureRule] momentum_failed? error: #{e.class} - #{e.message}")
        false
      end
    end
  end
end
