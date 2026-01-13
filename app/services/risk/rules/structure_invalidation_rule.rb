# frozen_string_literal: true

module Risk
  module Rules
    # Structure Invalidation Rule - PRIMARY EXIT for intraday options buying
    #
    # PURPOSE: Exit when trade thesis is broken by market structure failure
    #
    # This rule ignores PnL, % profit, trailing, and rupee targets.
    # If structure breaks AGAINST the position → GET OUT immediately.
    #
    # This is how professional options traders exit: structure-first, not PnL-first.
    #
    # Exit conditions:
    # - 1m or 5m structure breaks AGAINST position direction
    # - BOS/CHoCH invalidation detected
    # - Reclaim of broken level
    #
    # Priority: 20 (checked after hard rupee SL)
    class StructureInvalidationRule < BaseRule
      PRIORITY = 20

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        tracker = context.tracker
        instrument = tracker.instrument || tracker.watchable&.instrument
        return skip_result unless instrument

        # Get position direction from tracker metadata or instrument
        position_direction = determine_position_direction(tracker, instrument)
        return skip_result unless position_direction.in?(%i[bullish bearish])

        # Check structure invalidation on 1m and 5m timeframes
        if structure_invalidated?(instrument, position_direction)
          reason = "STRUCTURE_INVALIDATION (#{position_direction} structure broken)"
          return exit_result(reason: reason, metadata: { direction: position_direction })
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[StructureInvalidationRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      private

      # Determine position direction (bullish = CE/long, bearish = PE/short)
      def determine_position_direction(tracker, instrument)
        # Try to get from metadata first
        direction = tracker.meta&.dig('direction')&.to_sym
        return direction if direction.in?(%i[bullish bearish])

        # Infer from instrument symbol
        symbol = instrument&.symbol_name&.to_s&.upcase
        return :bullish if symbol&.include?('CE')
        return :bearish if symbol&.include?('PE')

        # Fallback: check underlying direction from entry metadata
        entry_metadata = tracker.meta&.dig('entry_metadata') || {}
        direction = entry_metadata['direction']&.to_sym
        return direction if direction.in?(%i[bullish bearish])

        nil
      end

      # Check if structure is invalidated on 1m or 5m
      def structure_invalidated?(instrument, position_direction)
        # Check 1m structure
        series_1m = instrument.candle_series(interval: '1')
        if series_1m&.candles&.any? && structure_broken?(series_1m.candles, position_direction)
          Rails.logger.debug { "[StructureInvalidationRule] 1m structure broken for #{position_direction}" }
          return true
        end

        # Check 5m structure
        series_5m = instrument.candle_series(interval: '5')
        if series_5m&.candles&.any? && structure_broken?(series_5m.candles, position_direction)
          Rails.logger.debug { "[StructureInvalidationRule] 5m structure broken for #{position_direction}" }
          return true
        end

        false
      rescue StandardError => e
        Rails.logger.error("[StructureInvalidationRule] structure_invalidated? error: #{e.class} - #{e.message}")
        false
      end

      # Check if structure is broken against position direction
      def structure_broken?(candles, position_direction)
        return false if candles.blank? || candles.size < 3

        # Check BOS failure (break of structure against position)
        if position_direction == :bullish
          # Bullish position: exit if price breaks below recent swing low
          recent_swing_low = candles.last(10).map(&:low).min
          current_close = candles.last&.close
          return true if current_close && recent_swing_low && current_close < recent_swing_low
        else
          # Bearish position: exit if price breaks above recent swing high
          recent_swing_high = candles.last(10).map(&:high).max
          current_close = candles.last&.close
          return true if current_close && recent_swing_high && current_close > recent_swing_high
        end

        # Check CHoCH (Change of Character) against position
        choch_dir = Entries::StructureDetector.choch?(candles, lookback_minutes: 15)
        if choch_dir && choch_dir != :neutral && choch_dir != position_direction
          Rails.logger.debug { "[StructureInvalidationRule] CHoCH detected: #{choch_dir} (position: #{position_direction})" }
          return true
        end

        false
      rescue StandardError => e
        Rails.logger.error("[StructureInvalidationRule] structure_broken? error: #{e.class} - #{e.message}")
        false
      end
    end
  end
end
