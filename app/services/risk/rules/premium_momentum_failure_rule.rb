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
        return skip_result unless tracker.created_at

        # Use the fresh LTP from context if available
        current_ltp = context.position.respond_to?(:current_ltp) ? context.position.current_ltp.to_f : nil
        current_ltp ||= tracker.entry_price.to_f # Fallback (should not happen in live)

        # Initialize or update peak premium in meta
        meta = tracker.meta || {}
        peak = meta['peak_premium'].to_f
        last_peak_at = meta['peak_premium_at'] ? Time.zone.parse(meta['peak_premium_at']) : tracker.created_at

        # Update peak if current LTP is higher
        if current_ltp > peak
          meta['peak_premium'] = current_ltp
          meta['peak_premium_at'] = Time.current.iso8601
          tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
          return no_action_result
        end

        # Check if stalled - ONLY for losing trades (Theta protection)
        # Winners are handled by trailing stop/peak drawdown logic
        return no_action_result if context.pnl_pct.to_f.positive?

        stall_minutes = DEFAULT_STALL_MINUTES
        elapsed_since_peak = (Time.current - last_peak_at) / 60.0

        if elapsed_since_peak >= stall_minutes
          reason = "PREMIUM_MOMENTUM_FAILURE (No new peak in #{elapsed_since_peak.round(1)} mins, Peak: #{peak.round(2)})"
          return exit_result(
            reason: reason,
            metadata: {
              peak: peak,
              current: current_ltp,
              elapsed_since_peak: elapsed_since_peak
            }
          )
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
        unless series&.candles&.any?
          Rails.logger.debug do
            "[PremiumMomentumFailureRule] No #{interval}m candle data for #{instrument.symbol_name} — skipping"
          end
          return false
        end

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
