# frozen_string_literal: true

module Orders
  # EntryManager for NEMESIS V3 architecture
  # Orchestrates entry order placement, validation, and position tracking
  # Integrates with Capital::Allocator, EntryGuard, Orders::Placer, and ActiveCache
  # rubocop:disable Metrics/ClassLength
  class EntryManager
    def initialize(event_bus: Core::EventBus.instance, active_cache: Positions::ActiveCache.instance)
      @event_bus = event_bus
      @active_cache = active_cache
      @stats = {
        entries_attempted: 0,
        entries_successful: 0,
        entries_failed: 0,
        validation_failures: 0,
        allocation_failures: 0
      }
    end

    # Process entry signal and place order
    # @param signal_result [Hash] Signal result with pick/candidate data
    # @param index_cfg [Hash] Index configuration
    # @param direction [Symbol] :bullish or :bearish
    # @param scale_multiplier [Integer] Scale multiplier for position sizing
    # @param trend_score [Float, nil] Trend score from TrendScorer (0-21)
    # @return [Hash] Result hash with :success, :tracker, :order_no, :error
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def process_entry(signal_result:, index_cfg:, direction:, scale_multiplier: 1, trend_score: nil)
      @stats[:entries_attempted] += 1

      # Extract pick/candidate from signal result
      pick = extract_pick(signal_result)
      return failure_result('No pick/candidate found in signal result') unless pick

      # Get dynamic risk percentage based on trend score
      risk_pct = if trend_score
                   risk_allocator = Capital::DynamicRiskAllocator.new
                   risk_allocator.risk_pct_for(
                     index_key: index_cfg[:key],
                     trend_score: trend_score
                   )
                 end

      # Log risk allocation for monitoring
      if risk_pct
        Rails.logger.info(
          "[Orders::EntryManager] Dynamic risk allocation for #{index_cfg[:key]}: " \
          "risk_pct=#{risk_pct.round(4)} (trend_score=#{trend_score})"
        )
      end

      # Validate entry using EntryGuard
      unless Entries::EntryGuard.try_enter(
        index_cfg: index_cfg,
        pick: pick,
        direction: direction,
        scale_multiplier: scale_multiplier
      )
        @stats[:validation_failures] += 1
        return failure_result('Entry validation failed')
      end

      # EntryGuard already placed the order and created PositionTracker
      # We need to find the tracker and add it to ActiveCache
      tracker = find_tracker_for_pick(pick, index_cfg)
      unless tracker
        @stats[:entries_failed] += 1
        return failure_result('PositionTracker not found after entry')
      end

      # Reject if quantity < 1 lot-equivalent
      lot_size = pick[:lot_size] || tracker.quantity.to_i # Fallback to quantity if lot_size missing
      if tracker.quantity.to_i < lot_size
        @stats[:entries_failed] += 1
        Rails.logger.warn("[Orders::EntryManager] Quantity #{tracker.quantity} < 1 lot (#{lot_size}) for #{tracker.order_no}")
        return failure_result("Quantity #{tracker.quantity} < 1 lot (#{lot_size})")
      end

      # Calculate SL/TP prices
      sl_price, tp_price = calculate_sl_tp(tracker.entry_price, direction)

      # Add to ActiveCache
      position_data = @active_cache.add_position(
        tracker: tracker,
        sl_price: sl_price,
        tp_price: tp_price
      )

      unless position_data
        Rails.logger.warn("[Orders::EntryManager] Failed to add position to ActiveCache: #{tracker.id}")
      end

      # Place bracket orders via BracketPlacer
      bracket_placer = Orders::BracketPlacer.new
      bracket_result = bracket_placer.place_bracket(
        tracker: tracker,
        sl_price: sl_price,
        tp_price: tp_price,
        reason: 'initial_bracket'
      )

      unless bracket_result[:success]
        Rails.logger.warn("[Orders::EntryManager] Bracket placement failed for #{tracker.order_no}: #{bracket_result[:error]}")
      end

      # NEW: Record trade in DailyLimits
      daily_limits = Live::DailyLimits.new
      daily_limits.record_trade(index_key: index_cfg[:key])

      # Emit entry_filled event
      emit_entry_filled_event(tracker, pick, index_cfg, direction, sl_price, tp_price, risk_pct)

      # Send Telegram notification
      notify_telegram_entry(tracker, pick, index_cfg, direction, sl_price, tp_price, risk_pct)

      @stats[:entries_successful] += 1
      success_result(
        tracker: tracker,
        position_data: position_data,
        sl_price: sl_price,
        tp_price: tp_price,
        bracket_result: bracket_result,
        risk_pct: risk_pct
      )
    rescue StandardError => e
      @stats[:entries_failed] += 1
      Rails.logger.error("[Orders::EntryManager] process_entry failed: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      failure_result(e.message)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # Get statistics
    # @return [Hash]
    def stats
      @stats.dup
    end

    private

    # Extract pick/candidate from signal result
    # Handles both old format (pick) and new format (candidate from DerivativeChainAnalyzer)
    # Also supports StrikeSelector output format
    # @param signal_result [Hash] Signal result
    # @return [Hash, nil] Pick/candidate hash
    def extract_pick(signal_result)
      # Try new format first (candidate from DerivativeChainAnalyzer)
      return signal_result[:candidate] if signal_result[:candidate]

      # Try StrikeSelector format (normalized instrument hash)
      if signal_result.is_a?(Hash) && signal_result[:security_id].present? && signal_result[:index].present?
        return signal_result
      end

      # Try old format (pick)
      return signal_result[:pick] if signal_result[:pick]

      # Try direct hash (signal_result itself might be the pick)
      return signal_result if signal_result.is_a?(Hash) && signal_result[:security_id].present?

      nil
    end

    # Find PositionTracker for a pick
    # @param pick [Hash] Pick/candidate data
    # @param index_cfg [Hash] Index configuration
    # @return [PositionTracker, nil]
    def find_tracker_for_pick(pick, index_cfg)
      segment = pick[:segment] || index_cfg[:segment]
      security_id = pick[:security_id]

      return nil unless segment.present? && security_id.present?

      # Try to find by security_id (most recent active)
      tracker = PositionTracker.active
                               .where(segment: segment, security_id: security_id.to_s)
                               .order(created_at: :desc)
                               .first

      return tracker if tracker

      # If not found, might be paper trading - check paper trackers
      PositionTracker.paper.active
                     .where(segment: segment, security_id: security_id.to_s)
                     .order(created_at: :desc)
                     .first
    end

    # Calculate SL/TP prices based on entry price and direction
    # @param entry_price [BigDecimal, Float] Entry price
    # @param direction [Symbol] :bullish or :bearish
    # @return [Array<Float, Float>] [sl_price, tp_price]
    def calculate_sl_tp(entry_price, direction)
      entry = entry_price.to_f
      return [nil, nil] unless entry.positive?

      # Default NEMESIS V3 values: SL = 30% below, TP = 60% above for long positions
      if direction == :bullish
        sl = entry * 0.70  # 30% below entry
        tp = entry * 1.60  # 60% above entry
      else
        # For bearish (PE), SL is above entry, TP is below entry
        sl = entry * 1.30  # 30% above entry
        tp = entry * 0.50  # 50% below entry (more conservative for PE)
      end

      [sl.round(2), tp.round(2)]
    end

    # Emit entry_filled event via EventBus
    # @param tracker [PositionTracker] PositionTracker instance
    # @param pick [Hash] Pick/candidate data
    # @param index_cfg [Hash] Index configuration
    # @param direction [Symbol] Direction
    # @param sl_price [Float] Stop loss price
    # @param tp_price [Float] Take profit price
    # @param risk_pct [Float, nil] Dynamic risk percentage
    # rubocop:disable Metrics/ParameterLists
    def emit_entry_filled_event(tracker, pick, index_cfg, direction, sl_price, tp_price,
                                risk_pct = nil)
      event_data = {
        tracker_id: tracker.id,
        order_no: tracker.order_no,
        segment: tracker.segment,
        security_id: tracker.security_id,
        symbol: pick[:symbol] || tracker.symbol,
        entry_price: tracker.entry_price.to_f,
        quantity: tracker.quantity.to_i,
        direction: direction,
        index_key: index_cfg[:key],
        sl_price: sl_price,
        tp_price: tp_price,
        risk_pct: risk_pct,
        timestamp: Time.current
      }

      @event_bus.publish(Core::EventBus::EVENTS[:entry_filled], event_data)
      Rails.logger.info("[Orders::EntryManager] Emitted entry_filled event for #{tracker.order_no}")
    rescue StandardError => e
      Rails.logger.error("[Orders::EntryManager] Failed to emit entry_filled event: #{e.class} - #{e.message}")
    end
    # rubocop:enable Metrics/ParameterLists

    # Build success result hash
    # @param tracker [PositionTracker] PositionTracker instance
    # @param position_data [PositionData] ActiveCache position data
    # @param sl_price [Float] Stop loss price
    # @param tp_price [Float] Take profit price
    # @param bracket_result [Hash, nil] Bracket placement result
    # @param risk_pct [Float, nil] Dynamic risk percentage
    # @return [Hash]
    # rubocop:disable Metrics/ParameterLists
    def success_result(tracker:, position_data:, sl_price:, tp_price:, bracket_result: nil, risk_pct: nil)
      {
        success: true,
        tracker: tracker,
        tracker_id: tracker.id,
        order_no: tracker.order_no,
        position_data: position_data,
        sl_price: sl_price,
        tp_price: tp_price,
        bracket_result: bracket_result,
        risk_pct: risk_pct
      }
    end
    # rubocop:enable Metrics/ParameterLists

    # Build failure result hash
    # @param error [String] Error message
    # @return [Hash]
    def failure_result(error)
      {
        success: false,
        error: error,
        tracker: nil,
        tracker_id: nil,
        order_no: nil
      }
    end

    # Send Telegram entry notification
    # @param tracker [PositionTracker] Position tracker
    # @param pick [Hash] Pick/candidate data
    # @param index_cfg [Hash] Index configuration
    # @param direction [Symbol] Direction
    # @param sl_price [Float] Stop loss price
    # @param tp_price [Float] Take profit price
    # @param risk_pct [Float, nil] Dynamic risk percentage
    def notify_telegram_entry(tracker, pick, index_cfg, direction, sl_price, tp_price, risk_pct)
      return unless telegram_enabled?

      entry_data = {
        symbol: pick[:symbol] || tracker.symbol,
        entry_price: tracker.entry_price.to_f,
        quantity: tracker.quantity.to_i,
        direction: direction,
        index_key: index_cfg[:key],
        risk_pct: risk_pct,
        sl_price: sl_price,
        tp_price: tp_price
      }

      Notifications::TelegramNotifier.instance.notify_entry(tracker, entry_data)
    rescue StandardError => e
      Rails.logger.error("[Orders::EntryManager] Telegram notification failed: #{e.class} - #{e.message}")
    end

    # Check if Telegram notifications are enabled
    # @return [Boolean]
    def telegram_enabled?
      config = AlgoConfig.fetch[:telegram] || {}
      enabled = config[:enabled] != false && config[:notify_entry] != false
      enabled && Notifications::TelegramNotifier.instance.enabled?
    rescue StandardError
      false
    end
  end
  # rubocop:enable Metrics/ClassLength
end
