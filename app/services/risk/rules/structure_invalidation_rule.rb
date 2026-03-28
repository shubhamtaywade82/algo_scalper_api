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
    # - 5m or 15m structure breaks AGAINST position direction (underlying)
    # - BOS/CHoCH invalidation detected
    # - Reclaim of broken level
    #
    # Priority: 20 (checked after hard rupee SL)
    class StructureInvalidationRule < BaseRule
      PRIORITY = 20

      def evaluate(context)
        tracker = context.tracker
        snapshot = context.tracker_snapshot
        return skip_result unless tracker && snapshot

        # Delegate to legacy method for parity and spec compatibility
        # This covers the 'structure_invalidation_price' and 'dual_condition' checks
        result = Live::UnifiedExitChecker.check_structure_invalidation(tracker, snapshot)
        
        if result && result[:exit]
          return exit_result(
            reason: result[:reason] || 'STRUCTURE_INVALIDATION',
            metadata: {
              path: 'structure_invalidation'
            }
          )
        end

        # Fallback to internal rules if legacy hasn't triggered yet
        instrument = tracker.instrument || tracker.watchable&.instrument
        return no_action_result unless instrument

        position_direction = determine_position_direction(tracker, instrument)
        return no_action_result unless position_direction

        if opposite_bos_confirmed?(tracker, instrument, position_direction)
          return exit_result(
            reason: "STRUCTURE_INVALIDATION (opposite BOS confirmed)",
            metadata: { direction: position_direction, path: 'structure_invalidation' }
          )
        end

        # Multi-timeframe structure check
        if structure_invalidated?(instrument, position_direction)
          return exit_result(
            reason: "STRUCTURE_INVALIDATION (#{position_direction} structure broken)",
            metadata: { direction: position_direction, path: 'structure_invalidation' }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[StructureInvalidationRule] Error: #{e.class} - #{e.message}")
        no_action_result
      end

      private

      def resolve_underlying_ltp(index_key)
        # Use existing module logic to fetch LTP
        Live::UnifiedExitChecker.resolve_underlying_ltp(index_key)
      end

      def structure_invalidated_by_price?(tracker, underlying_ltp, invalidation_price)
        direction = tracker.meta&.dig('direction').to_s
        level = invalidation_price.to_f
        buffer = structure_invalidation_buffer(level)
        case direction
        when 'long_pe', 'bearish'
          underlying_ltp > level + buffer
        when 'long_ce', 'bullish'
          underlying_ltp < level - buffer
        else
          false
        end
      end

      def structure_invalidation_buffer(level)
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}
        pct = (cfg[:buffer_pct] || 0.002).to_f
        (level * pct).abs
      end

      def dual_condition_met?(tracker, underlying_ltp, premium_ltp, cfg)
        # Ported from legacy UnifiedExitChecker
        entry_underlying = tracker.meta&.dig('entry_underlying_price').to_f
        return false if entry_underlying.zero?

        move_pct = (underlying_ltp - entry_underlying).abs / entry_underlying
        return false if move_pct < cfg[:underlying_move_pct].to_f

        entry_premium = tracker.entry_price.to_f
        return false if entry_premium.zero?

        drop_pct = (entry_premium - premium_ltp) / entry_premium
        drop_pct >= cfg[:premium_drop_pct].to_f
      end

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

      # Check if structure is invalidated on 5m or 15m timeframes (underlying)
      def structure_invalidated?(instrument, position_direction)
        # Check 5m structure first
        series_5m = instrument.candle_series(interval: '5')
        if series_5m&.candles&.any? && structure_broken?(series_5m.candles, position_direction)
          Rails.logger.debug { "[StructureInvalidationRule] 5m structure broken for #{position_direction}" }
          return true
        end

        # Check 15m structure
        series_15m = instrument.candle_series(interval: '15')
        if series_15m&.candles&.any? && structure_broken?(series_15m.candles, position_direction)
          Rails.logger.debug { "[StructureInvalidationRule] 15m structure broken for #{position_direction}" }
          return true
        end

        false
      rescue StandardError => e
        Rails.logger.error("[StructureInvalidationRule] structure_invalidated? error: #{e.class} - #{e.message}")
        false
      end

      def opposite_bos_confirmed?(tracker, instrument, position_direction)
        timeframe = tracker.meta&.dig('bos_timeframe') || tracker.meta&.dig('entry_timeframe') || '5m'
        interval = timeframe.to_s.gsub(/[^0-9]/, '')
        return false if interval.blank?

        series = instrument.candle_series(interval: interval)
        bos = Entries::BosExtractor.last_confirmed_bos(series, lookback: 5)
        return false unless bos

        return false if bos[:direction] == position_direction

        confirmed_at = bos[:confirmed_at]
        return false unless confirmed_at && tracker.created_at

        confirmed_at > tracker.created_at
      rescue StandardError => e
        Rails.logger.error("[StructureInvalidationRule] opposite_bos_confirmed? error: #{e.class} - #{e.message}")
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
