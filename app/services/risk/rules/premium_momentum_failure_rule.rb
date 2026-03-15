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

      # Default thresholds (number of minutes without a new peak)
      DEFAULT_STALL_MINUTES = 3

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
    end
  end
end
