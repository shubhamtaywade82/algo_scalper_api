# frozen_string_literal: true

module Risk
  module Rules
    # Structural kill switch exit for the underlying.
    #
    # Triggers immediately if the underlying breaks any of:
    #   1. VWAP
    #   2. 9-EMA
    #   3. Most recent 3-candle swing low (CE) / swing high (PE)
    #
    # Each break requires a configurable tolerance beyond the level to avoid
    # wick noise. No additional data dependencies beyond the existing
    # Live::CandleSeriesCache (1m interval, no backfill for live speed).
    class StructuralKillSwitchRule < BaseRule
      PRIORITY = 22

      DEFAULT_TOLERANCE_PCT = 0.002 # 0.2% — strict break confirmation

      def evaluate(context)
        return skip_result unless context.active?
        return no_action_result unless enabled?(context)

        tracker = context.tracker
        underlying_ltp = current_underlying_ltp(tracker)
        return no_action_result unless underlying_ltp&.positive?

        direction = (tracker.meta || {})['direction'].to_s
        return no_action_result if direction.blank?

        index_instrument = resolve_index_instrument(tracker)
        return no_action_result unless index_instrument

        series = Live::CandleSeriesCache.fetch(instrument: index_instrument, interval: 1, backfill: false)
        return no_action_result unless series&.candles&.size&.>= 10

        vwap = series.current_vwap
        ema9 = series.ema(9)
        return no_action_result unless vwap && ema9

        tolerance = config.fetch(:tolerance_pct, DEFAULT_TOLERANCE_PCT).to_f

        if vwap_broken?(direction, underlying_ltp, vwap, tolerance)
          return exit_result(
            reason: 'STRUCTURAL_KILL_VWAP',
            metadata: { path: 'structural_kill_switch', vwap: format(vwap), ltp: format(underlying_ltp) }
          )
        end

        if ema9_broken?(direction, underlying_ltp, ema9, tolerance)
          return exit_result(
            reason: 'STRUCTURAL_KILL_EMA9',
            metadata: { path: 'structural_kill_switch', ema9: format(ema9), ltp: format(underlying_ltp) }
          )
        end

        swing_level = recent_swing_level(series, direction)
        if swing_level && swing_broken?(direction, underlying_ltp, swing_level, tolerance)
          return exit_result(
            reason: 'STRUCTURAL_KILL_SWING',
            metadata: { path: 'structural_kill_switch', swing_level: format(swing_level), ltp: format(underlying_ltp) }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[StructuralKillSwitchRule] evaluation error for tracker=#{tracker&.id}: #{e.class} - #{e.message}")
        no_action_result
      end

      private

      def current_underlying_ltp(tracker)
        if tracker.respond_to?(:watchable) && tracker.watchable.respond_to?(:instrument)
          underlying = tracker.watchable.instrument
          return nil unless underlying

          Live::TickQuery.for_security(segment: underlying.exchange_segment, security_id: underlying.underlying_security_id)&.ltp&.to_f
        end
      rescue StandardError
        nil
      end

      def resolve_index_instrument(tracker)
        meta = tracker.meta || {}
        index_key = meta['index_key'].to_s
        return nil if index_key.blank?

        if tracker.respond_to?(:watchable) && tracker.watchable.respond_to?(:instrument)
          underlying = tracker.watchable.instrument
          return nil unless underlying

          IndexInstrumentCache.instance.get_or_fetch(
            key: index_key,
            sid: underlying.underlying_security_id,
            segment: underlying.exchange_segment
          )
        else
          Instrument.find_by(symbol_name: index_key, segment: 'index')
        end
      rescue StandardError
        nil
      end

      def bullish_direction?(direction)
        %w[long_ce bullish call ce].include?(direction)
      end

      def bearish_direction?(direction)
        %w[long_pe bearish put pe].include?(direction)
      end

      def vwap_broken?(direction, ltp, vwap, tolerance)
        if bullish_direction?(direction)
          ltp < (vwap * (1.0 - tolerance))
        elsif bearish_direction?(direction)
          ltp > (vwap * (1.0 + tolerance))
        else
          false
        end
      end

      def ema9_broken?(direction, ltp, ema9, tolerance)
        if bullish_direction?(direction)
          ltp < (ema9 * (1.0 - tolerance))
        elsif bearish_direction?(direction)
          ltp > (ema9 * (1.0 + tolerance))
        else
          false
        end
      end

      # Find the most recent confirmed swing in a bounded lookback.
      def recent_swing_level(series, direction)
        lookback = [series.candles.size - 2, 29].min
        (0..lookback).reverse_each do |i|
          next unless series.candles[i]

          if bullish_direction?(direction)
            return series.candles[i].low if series.respond_to?(:swing_low?) && series.swing_low?(i)
          elsif bearish_direction?(direction)
            return series.candles[i].high if series.respond_to?(:swing_high?) && series.swing_high?(i)
          end
        end
        nil
      end

      def swing_broken?(direction, ltp, swing_level, tolerance)
        if bullish_direction?(direction)
          ltp < swing_level * (1.0 - tolerance)
        elsif bearish_direction?(direction)
          ltp > swing_level * (1.0 + tolerance)
        else
          false
        end
      end

      def format(value)
        value&.round(2)
      end
    end
  end
end
