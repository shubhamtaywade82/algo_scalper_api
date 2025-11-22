# frozen_string_literal: true

module Orders
  # BracketPlacer for NEMESIS V3 architecture
  # Places and manages SL/TP bracket orders for positions
  # Supports initial bracket placement and dynamic adjustments
  # rubocop:disable Metrics/ClassLength
  class BracketPlacer
    def initialize(event_bus: Core::EventBus.instance, active_cache: Positions::ActiveCache.instance)
      @event_bus = event_bus
      @active_cache = active_cache
      @stats = {
        brackets_placed: 0,
        brackets_modified: 0,
        brackets_failed: 0,
        sl_orders_placed: 0,
        tp_orders_placed: 0
      }
    end

    # Place bracket orders (SL/TP) for a position
    # Note: DhanHQ bracket orders are placed WITH the entry order (boProfitValue, boStopLossValue)
    # This method is for cases where bracket orders need to be placed separately or modified
    # @param tracker [PositionTracker] PositionTracker instance
    # @param sl_price [Float] Stop loss price
    # @param tp_price [Float] Take profit price
    # @param reason [String] Reason for bracket placement
    # @return [Hash] Result hash with :success, :sl_order, :tp_order, :error
    def place_bracket(tracker:, sl_price:, tp_price:, reason: nil)
      return failure_result('Tracker not found') unless tracker
      return failure_result('Tracker not active') unless tracker.active?
      return failure_result('Invalid SL/TP prices') unless sl_price&.positive? && tp_price&.positive?

      # For NEMESIS V3, bracket orders are typically placed WITH the entry order
      # This method is primarily for adjustments or separate placement scenarios
      # DhanHQ doesn't support modifying bracket orders - we'd need to cancel and replace
      # For now, we'll update ActiveCache and log the bracket levels

      # Update ActiveCache with SL/TP
      @active_cache.update_position(
        tracker.id,
        sl_price: sl_price,
        tp_price: tp_price
      )

      # Emit bracket placed event
      emit_bracket_placed_event(tracker, sl_price, tp_price, reason)

      @stats[:brackets_placed] += 1
      @stats[:sl_orders_placed] += 1
      @stats[:tp_orders_placed] += 1

      success_result(sl_price: sl_price, tp_price: tp_price, reason: reason)
    rescue StandardError => e
      @stats[:brackets_failed] += 1
      Rails.logger.error("[Orders::BracketPlacer] place_bracket failed: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      failure_result(e.message)
    end

    # Update bracket orders (modify SL/TP)
    # Since DhanHQ doesn't support modifying bracket orders, this updates ActiveCache
    # The actual order modification would require canceling and replacing (not implemented here)
    # @param tracker [PositionTracker] PositionTracker instance
    # @param sl_price [Float, nil] New stop loss price (nil to keep existing)
    # @param tp_price [Float, nil] New take profit price (nil to keep existing)
    # @param reason [String] Reason for modification
    # @return [Hash] Result hash with :success, :sl_price, :tp_price, :error
    # rubocop:disable Metrics/AbcSize
    def update_bracket(tracker:, sl_price: nil, tp_price: nil, reason: nil)
      return failure_result('Tracker not found') unless tracker
      return failure_result('Tracker not active') unless tracker.active?

      # Get current bracket levels from ActiveCache
      position = @active_cache.get_by_tracker_id(tracker.id)
      return failure_result('Position not found in ActiveCache') unless position

      new_sl = sl_price || position.sl_price
      new_tp = tp_price || position.tp_price

      return failure_result('Invalid SL/TP prices') unless new_sl&.positive? && new_tp&.positive?

      # Update ActiveCache
      updates = {}
      updates[:sl_price] = new_sl if sl_price
      updates[:tp_price] = new_tp if tp_price

      @active_cache.update_position(tracker.id, **updates)

      # Emit bracket modified event
      emit_bracket_modified_event(tracker, new_sl, new_tp, reason)

      @stats[:brackets_modified] += 1

      success_result(sl_price: new_sl, tp_price: new_tp, reason: reason)
    rescue StandardError => e
      @stats[:brackets_failed] += 1
      Rails.logger.error("[Orders::BracketPlacer] update_bracket failed: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      failure_result(e.message)
    end
    # rubocop:enable Metrics/AbcSize

    # Move SL to breakeven (entry price)
    # @param tracker [PositionTracker] PositionTracker instance
    # @param reason [String] Reason for breakeven move
    # @return [Hash] Result hash
    def move_to_breakeven(tracker:, reason: 'breakeven_lock')
      return failure_result('Tracker not found') unless tracker
      return failure_result('Tracker not active') unless tracker.active?

      entry_price = tracker.entry_price.to_f
      return failure_result('Invalid entry price') unless entry_price.positive?

      # Update SL to entry price (breakeven)
      update_bracket(tracker: tracker, sl_price: entry_price, reason: reason)
    end

    # Move SL to trailing stop price
    # @param tracker [PositionTracker] PositionTracker instance
    # @param trailing_price [Float] Trailing stop price
    # @param reason [String] Reason for trailing move
    # @return [Hash] Result hash
    def move_to_trailing(tracker:, trailing_price:, reason: 'trailing_stop')
      return failure_result('Tracker not found') unless tracker
      return failure_result('Tracker not active') unless tracker.active?

      return failure_result('Invalid trailing price') unless trailing_price&.positive?

      # Update SL to trailing price
      update_bracket(tracker: tracker, sl_price: trailing_price, reason: reason)
    end

    # Get statistics
    # @return [Hash]
    def stats
      @stats.dup
    end

    private

    # Emit bracket placed event via EventBus
    # @param tracker [PositionTracker] PositionTracker instance
    # @param sl_price [Float] Stop loss price
    # @param tp_price [Float] Take profit price
    # @param reason [String] Reason
    def emit_bracket_placed_event(tracker, sl_price, tp_price, reason)
      event_data = {
        tracker_id: tracker.id,
        order_no: tracker.order_no,
        segment: tracker.segment,
        security_id: tracker.security_id,
        sl_price: sl_price,
        tp_price: tp_price,
        reason: reason,
        timestamp: Time.current
      }

      @event_bus.publish(Core::EventBus::EVENTS[:bracket_placed] || :bracket_placed, event_data)
      Rails.logger.info("[Orders::BracketPlacer] Emitted bracket_placed event for #{tracker.order_no}")
    rescue StandardError => e
      Rails.logger.error("[Orders::BracketPlacer] Failed to emit bracket_placed event: #{e.class} - #{e.message}")
    end

    # Emit bracket modified event via EventBus
    # @param tracker [PositionTracker] PositionTracker instance
    # @param sl_price [Float] New stop loss price
    # @param tp_price [Float] New take profit price
    # @param reason [String] Reason
    def emit_bracket_modified_event(tracker, sl_price, tp_price, reason)
      event_data = {
        tracker_id: tracker.id,
        order_no: tracker.order_no,
        segment: tracker.segment,
        security_id: tracker.security_id,
        sl_price: sl_price,
        tp_price: tp_price,
        reason: reason,
        timestamp: Time.current
      }

      @event_bus.publish(Core::EventBus::EVENTS[:bracket_modified] || :bracket_modified, event_data)
      Rails.logger.info("[Orders::BracketPlacer] Emitted bracket_modified event for #{tracker.order_no}")
    rescue StandardError => e
      Rails.logger.error("[Orders::BracketPlacer] Failed to emit bracket_modified event: #{e.class} - #{e.message}")
    end

    # Build success result hash
    # @param sl_price [Float] Stop loss price
    # @param tp_price [Float] Take profit price
    # @param reason [String] Reason
    # @return [Hash]
    def success_result(sl_price:, tp_price:, reason: nil)
      {
        success: true,
        sl_price: sl_price,
        tp_price: tp_price,
        reason: reason
      }
    end

    # Build failure result hash
    # @param error [String] Error message
    # @return [Hash]
    def failure_result(error)
      {
        success: false,
        error: error,
        sl_price: nil,
        tp_price: nil
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
