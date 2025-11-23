# frozen_string_literal: true

module Live
  # TrailingEngine for NEMESIS V3
  # Per-tick trailing stop management with tiered SL offsets
  # Updates peak profit percentage and applies dynamic SL adjustments
  # rubocop:disable Metrics/ClassLength
  class TrailingEngine
    def initialize(active_cache: Positions::ActiveCache.instance,
                   bracket_placer: nil)
      @active_cache = active_cache
      @bracket_placer = bracket_placer || Orders::BracketPlacer.new
    end

    # Process tick for a position (called per-tick by RiskManager)
    # @param position_data [Positions::ActiveCache::PositionData] Position data from ActiveCache
    # @param exit_engine [Live::ExitEngine, nil] Exit engine for peak-drawdown exits
    # @return [Hash] Result hash with :peak_updated, :sl_updated, :exit_triggered, :error
    def process_tick(position_data, exit_engine: nil)
      return failure_result('Invalid position data') unless position_data&.valid?

      # 1. Check peak-drawdown FIRST (before any SL adjustments)
      if exit_engine && check_peak_drawdown(position_data, exit_engine)
        return {
          peak_updated: false,
          sl_updated: false,
          exit_triggered: true,
          reason: 'peak_drawdown_exit'
        }
      end

      # 2. Update peak_profit_pct if current profit exceeds peak
      peak_updated = update_peak(position_data)

      # 3. Apply tiered SL offsets based on current profit %
      sl_result = apply_tiered_sl(position_data)

      {
        peak_updated: peak_updated,
        sl_updated: sl_result[:updated],
        exit_triggered: false,
        new_sl_price: sl_result[:new_sl_price],
        reason: sl_result[:reason]
      }
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] process_tick failed: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      failure_result(e.message)
    end

    # Check if peak drawdown threshold is breached
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @param exit_engine [Live::ExitEngine] Exit engine instance
    # @return [Boolean] True if exit was triggered
    def check_peak_drawdown(position_data, exit_engine)
      return false unless exit_engine && position_data.peak_profit_pct

      peak = position_data.peak_profit_pct.to_f
      current = position_data.pnl_pct.to_f

      return false unless Positions::TrailingConfig.peak_drawdown_triggered?(peak, current)

      # Immediate exit - no candle close wait
      tracker = PositionTracker.find_by(id: position_data.tracker_id)
      unless tracker&.active?
        Rails.logger.warn("[TrailingEngine] Tracker #{position_data.tracker_id} not found or inactive for peak-drawdown exit")
        return false
      end

      drawdown = peak - current
      reason = "peak_drawdown_exit (drawdown: #{drawdown.round(2)}%)"

      exit_engine.execute_exit(tracker, reason)
      Rails.logger.warn("[TrailingEngine] Peak drawdown exit triggered for #{tracker.order_no}: #{reason}")

      true
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] Peak drawdown check failed: #{e.class} - #{e.message}")
      false
    end

    # Update peak profit percentage if current exceeds peak
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @return [Boolean] True if peak was updated
    def update_peak(position_data)
      return false unless position_data.pnl_pct && position_data.peak_profit_pct

      current = position_data.pnl_pct.to_f
      peak = position_data.peak_profit_pct.to_f

      return false if current <= peak

      # Update peak in ActiveCache
      @active_cache.update_position(
        position_data.tracker_id,
        peak_profit_pct: current
      )

      Rails.logger.debug { "[TrailingEngine] Updated peak_profit_pct for #{position_data.tracker_id}: #{peak.round(2)}% → #{current.round(2)}%" }
      true
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] Failed to update peak: #{e.class} - #{e.message}")
      false
    end

    # Apply tiered SL offsets based on current profit percentage
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @return [Hash] Result hash with :updated, :new_sl_price, :reason
    # rubocop:disable Metrics/AbcSize
    def apply_tiered_sl(position_data)
      return { updated: false, new_sl_price: nil, reason: 'invalid_position' } unless position_data.valid?

      entry_price = position_data.entry_price.to_f
      current_profit_pct = position_data.pnl_pct.to_f
      current_sl = position_data.sl_price.to_f

      # Calculate new SL based on tiered offsets
      new_sl_price = Positions::TrailingConfig.calculate_sl_price(entry_price, current_profit_pct)
      return { updated: false, new_sl_price: nil, reason: 'invalid_sl_calculation' } unless new_sl_price&.positive?

      # Only move SL if new_sl > current_sl (for long positions - trailing up)
      return { updated: false, new_sl_price: current_sl, reason: 'sl_not_improved' } unless new_sl_price > current_sl

      # Update SL via BracketPlacer
      tracker = PositionTracker.find_by(id: position_data.tracker_id)
      return { updated: false, new_sl_price: current_sl, reason: 'tracker_not_found' } unless tracker&.active?

      bracket_result = @bracket_placer.update_bracket(
        tracker: tracker,
        sl_price: new_sl_price,
        reason: "tiered_trailing (profit: #{current_profit_pct.round(2)}%)"
      )

      if bracket_result[:success]
        Rails.logger.info(
          "[TrailingEngine] Updated SL for #{tracker.order_no}: " \
          "₹#{current_sl.round(2)} → ₹#{new_sl_price.round(2)} " \
          "(profit: #{current_profit_pct.round(2)}%)"
        )
        { updated: true, new_sl_price: new_sl_price, reason: 'sl_updated' }
      else
        Rails.logger.warn("[TrailingEngine] Failed to update SL for #{tracker.order_no}: #{bracket_result[:error]}")
        { updated: false, new_sl_price: current_sl, reason: bracket_result[:error] }
      end
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] Failed to apply tiered SL: #{e.class} - #{e.message}")
      { updated: false, new_sl_price: nil, reason: e.message }
    end
    # rubocop:enable Metrics/AbcSize

    private

    # Build failure result hash
    # @param error [String] Error message
    # @return [Hash]
    def failure_result(error)
      {
        peak_updated: false,
        sl_updated: false,
        exit_triggered: false,
        error: error
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
