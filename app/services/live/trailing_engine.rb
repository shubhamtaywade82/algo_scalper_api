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
    def process_tick(position_data, exit_engine: nil, tracker: nil, pending_meta: nil)
      return failure_result('Invalid position data') unless position_data&.valid?

      # Use passed tracker or find if not provided (fallback for other callers)
      tracker ||= PositionTracker.find_by(id: position_data.tracker_id)
      return failure_result('Tracker not found') unless tracker

      # 1. Check peak-drawdown FIRST (before any SL adjustments)
      if exit_engine && check_peak_drawdown(position_data, exit_engine, tracker: tracker)
        return {
          peak_updated: false,
          sl_updated: false,
          exit_triggered: true,
          reason: 'peak_drawdown_exit'
        }
      end

      # 2. Update peak_profit_pct if current profit exceeds peak
      peak_updated = update_peak(position_data, tracker: tracker, pending_meta: pending_meta)

      # 3. Apply trailing SL (direct or tiered based on config)
      trailing = trailing_for(tracker)
      sl_result = if tailored_trailing_applicable?(position_data)
                    apply_tailored_sl(position_data, tracker: tracker)
                  elsif trailing.direct_trailing_enabled?
                    apply_direct_trailing_sl(position_data, tracker: tracker, trailing: trailing)
                  else
                    apply_tiered_sl(position_data, tracker: tracker, trailing: trailing)
                  end

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
    # Enhanced with peak-drawdown activation gating and capital-based thresholds
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @param exit_engine [Live::ExitEngine] Exit engine instance
    # @return [Boolean] True if exit was triggered
    def check_peak_drawdown(position_data, exit_engine, tracker: nil)
      return false unless exit_engine && position_data.peak_profit_pct

      # peak and current are decimal (e.g. 0.05 for 5%)
      peak = position_data.peak_profit_pct.to_f
      current = position_data.pnl_pct.to_f

      # Skip if peak is 0% or negative (position never profitable)
      # Peak drawdown rule should only trigger when position had profit and is drawing down
      if peak <= 0
        Rails.logger.debug do
          "[TrailingEngine] Skipping peak drawdown check: peak=#{(peak * 100).round(2)}% <= 0% " \
            '(position never profitable)'
        end
        return false
      end

      # Emergency defense-in-depth: sub-second path in UnifiedExitChecker is primary
      tracker ||= PositionTracker.find_by(id: position_data.tracker_id)
      drawdown_cfg = Positions::ExitConfigResolver.for(tracker).dig(:position_sizing, :drawdown) || {}
      unless drawdown_cfg[:emergency_peak_loss_exit] == false
        emergency_min_peak = (drawdown_cfg[:emergency_min_peak_pct] || 0.10).to_f
        if peak >= emergency_min_peak && current < -0.02 && tracker&.active?
            reason = "emergency_peak_loss_exit (peak: #{(peak * 100).round(2)}%, current: #{(current * 100).round(2)}%)"
            Live::ExitEngine.execute_exit(tracker: tracker, reason: reason, source: :trailing_engine)
            return true
        end
      end

      # Calculate capital deployed (entry_price * quantity)
      capital_deployed = calculate_capital_deployed(position_data)

      # Check if drawdown threshold is breached (with capital-aware thresholds)
      trailing = trailing_for(tracker)
      return false unless trailing.peak_drawdown_triggered?(
        peak,
        current,
        _capital_deployed: capital_deployed
      )

      # Apply peak-drawdown activation gating (if enabled)
      if peak_drawdown_activation_enabled?
        activation_ready = trailing.peak_drawdown_active?(
          profit_pct: peak,
          current_sl_offset_pct: current_sl_offset_pct_decimal(position_data)
        )
        unless activation_ready
          capital_info = capital_deployed ? " capital=₹#{capital_deployed.round(0)}" : ''
          Rails.logger.debug do
            "[TrailingEngine] Peak drawdown gating: peak=#{(peak * 100).round(2)}% " \
              "sl_offset=#{current_sl_offset_pct(position_data)&.round(2)}% " \
              "not activated (drawdown=#{(peak - current) * 100.round(2)}%#{capital_info})"
          end
          return false
        end
      end

      tracker ||= PositionTracker.find_by(id: position_data.tracker_id)
      unless tracker&.active?
        Rails.logger.warn("[TrailingEngine] Tracker #{position_data.tracker_id} not found or inactive for peak-drawdown exit")
        return false
      end

      drawdown_pct = (peak - current) * 100.0
      threshold = trailing.calculate_tiered_drawdown_threshold(peak)
      capital_info = capital_deployed ? " (capital: ₹#{capital_deployed.round(0)})" : ''
      reason = "peak_drawdown_exit (drawdown: #{drawdown_pct.round(2)}%, threshold: #{(threshold * 100).round(2)}%, peak: #{(peak * 100).round(2)}%#{capital_info})"

      # Wrap exit in tracker lock for idempotency
      tracker.with_lock do
        return false if tracker.exited?

        exit_engine.execute_exit(tracker, reason)
        Rails.logger.warn("[TrailingEngine] Peak drawdown exit triggered for #{tracker.order_no}: #{reason}")
        increment_peak_drawdown_metric
        true
      end
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] Peak drawdown check failed: #{e.class} - #{e.message}")
      false
    end

    # Update peak profit percentage if current exceeds peak
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @param tracker [PositionTracker] Tracker object
    # @return [Boolean] True if peak was updated
    def update_peak(position_data, tracker: nil, pending_meta: nil)
      return false unless position_data.pnl_pct && position_data.peak_profit_pct

      current = position_data.pnl_pct.to_f
      peak = position_data.peak_profit_pct.to_f
      min_profit = position_data.min_profit_pct.to_f

      peak_updated = current > peak
      min_updated = min_profit < peak

      if peak_updated
        # Update peak in ActiveCache (in-memory only)
        @active_cache.update_position(
          position_data.tracker_id,
          peak_profit_pct: current
        )
      end

      # Only persist to DB when extremes actually change
      return peak_updated unless peak_updated || min_updated

      entry_price = position_data.entry_price.to_f
      return peak_updated unless entry_price.positive?

      highest_price = entry_price * (1.0 + current)
      lowest_price = entry_price * (1.0 + min_profit)

      persist_extremes_if_changed(position_data.tracker_id, highest_price, lowest_price, tracker: tracker, pending_meta: pending_meta)

      if peak_updated
        Rails.logger.debug { "[TrailingEngine] Updated peak_profit_pct for #{position_data.tracker_id}: #{(peak * 100).round(2)}% → #{(current * 100).round(2)}% (Highest: ₹#{highest_price.round(2)})" }
      end

      peak_updated
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] Failed to update extremes: #{e.class} - #{e.message}")
      false
    end

    # Persist extremes to tracker meta only when values change
    # @param tracker_id [Integer] Tracker ID
    # @param highest_price [Float] New highest price
    # @param lowest_price [Float] New lowest price
    # @param tracker [PositionTracker] Tracker object
    def persist_extremes_if_changed(tracker_id, highest_price, lowest_price, tracker: nil, pending_meta: nil)
      tracker ||= PositionTracker.find_by(id: tracker_id)
      return unless tracker

      meta = (pending_meta || tracker.meta || {}).stringify_keys
      old_highest = meta['highest_price'].to_f
      old_lowest = meta['lowest_price']

      new_highest = [old_highest, highest_price].max
      new_lowest = old_lowest.nil? ? lowest_price : [old_lowest.to_f, lowest_price].min

      # Only write to DB if values actually changed
      return if new_highest == old_highest && new_lowest == old_lowest.to_f

      meta['highest_price'] = new_highest
      meta['lowest_price'] = new_lowest

      if pending_meta
        pending_meta['highest_price'] = new_highest
        pending_meta['lowest_price'] = new_lowest
      elsif tracker.exit_requested_at.blank? && tracker.exit_sent_at.blank? && !tracker.exited?
        tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # Apply direct trailing SL (follows price directly, only moves upward)
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @return [Hash] Result hash with :updated, :new_sl_price, :reason
    # rubocop:disable Metrics/AbcSize
    def apply_direct_trailing_sl(position_data, tracker: nil, trailing: nil)
      return { updated: false, new_sl_price: nil, reason: 'invalid_position' } unless position_data.valid?

      entry_price = position_data.entry_price.to_f
      current_price = position_data.current_ltp.to_f
      current_profit_pct = position_data.pnl_pct.to_f # decimal
      current_sl = position_data.sl_price.to_f

      return { updated: false, new_sl_price: current_sl, reason: 'no_current_price' } unless current_price.positive?

      tracker ||= PositionTracker.find_by(id: position_data.tracker_id)
      trailing ||= trailing_for(tracker)

      # Calculate new SL based on current price (maintains fixed distance below)
      new_sl_price = trailing.calculate_direct_trailing_sl(
        current_price: current_price,
        entry_price: entry_price,
        current_profit_pct: current_profit_pct
      )

      return { updated: false, new_sl_price: current_sl, reason: 'direct_trailing_not_applicable' } unless new_sl_price

      # Only update if new SL is higher than current SL (only moves upward)
      return { updated: false, new_sl_price: current_sl, reason: 'sl_not_improved' } unless new_sl_price > current_sl

      return { updated: false, new_sl_price: current_sl, reason: 'tracker_not_found' } unless tracker&.active?

      # Calculate SL offset for logging
      sl_offset_pct = ((new_sl_price - entry_price) / entry_price * 100.0).round(2)

      bracket_result = @bracket_placer.update_bracket(
        tracker: tracker,
        sl_price: new_sl_price,
        reason: "direct_trailing (price: ₹#{current_price.round(2)}, profit: #{(current_profit_pct * 100.0).round(2)}%)"
      )

      if bracket_result[:success]
        @active_cache.update_position(
          position_data.tracker_id,
          sl_price: new_sl_price,
          sl_offset_pct: sl_offset_pct
        )
        position_data.sl_price = new_sl_price if position_data.respond_to?(:sl_price=)
        position_data.sl_offset_pct = sl_offset_pct if position_data.respond_to?(:sl_offset_pct=)

        Rails.logger.info(
          "[TrailingEngine] Updated SL (direct trailing) for #{tracker.order_no}: " \
          "₹#{current_sl.round(2)} → ₹#{new_sl_price.round(2)} " \
          "(price: ₹#{current_price.round(2)}, profit: #{(current_profit_pct * 100.0).round(2)}%)"
        )
        { updated: true, new_sl_price: new_sl_price, reason: 'sl_updated' }
      else
        Rails.logger.warn("[TrailingEngine] Failed to update SL (direct trailing) for #{tracker.order_no}: #{bracket_result[:error]}")
        { updated: false, new_sl_price: current_sl, reason: bracket_result[:error] }
      end
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] Failed to apply direct trailing SL: #{e.class} - #{e.message}")
      { updated: false, new_sl_price: nil, reason: e.message }
    end
    # rubocop:enable Metrics/AbcSize

    # Apply tiered SL offsets based on current profit percentage
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @return [Hash] Result hash with :updated, :new_sl_price, :reason
    # rubocop:disable Metrics/AbcSize
    def apply_tiered_sl(position_data, tracker: nil, trailing: nil)
      return { updated: false, new_sl_price: nil, reason: 'invalid_position' } unless position_data.valid?

      entry_price = position_data.entry_price.to_f
      current_profit_pct = position_data.pnl_pct.to_f # decimal (e.g. 0.05 for 5%)
      current_sl = position_data.sl_price.to_f

      tracker ||= PositionTracker.find_by(id: position_data.tracker_id)
      trailing ||= trailing_for(tracker)

      sl_offset_pct = trailing.sl_offset_for(current_profit_pct)
      return { updated: false, new_sl_price: current_sl, reason: 'tier_not_reached' } unless sl_offset_pct

      new_sl_price = trailing.sl_price_from_entry(entry_price, sl_offset_pct)
      return { updated: false, new_sl_price: nil, reason: 'invalid_sl_calculation' } unless new_sl_price.positive?

      return { updated: false, new_sl_price: current_sl, reason: 'sl_not_improved' } unless new_sl_price > current_sl

      return { updated: false, new_sl_price: current_sl, reason: 'tracker_not_found' } unless tracker&.active?

      bracket_result = @bracket_placer.update_bracket(
        tracker: tracker,
        sl_price: new_sl_price,
        reason: "tiered_trailing (profit: #{(current_profit_pct * 100.0).round(2)}%)"
      )

      if bracket_result[:success]
        @active_cache.update_position(
          position_data.tracker_id,
          sl_price: new_sl_price,
          sl_offset_pct: sl_offset_pct
        )
        position_data.sl_price = new_sl_price if position_data.respond_to?(:sl_price=)
        position_data.sl_offset_pct = sl_offset_pct if position_data.respond_to?(:sl_offset_pct=)

        Rails.logger.info(
          "[TrailingEngine] Updated SL for #{tracker.order_no}: " \
          "₹#{current_sl.round(2)} → ₹#{new_sl_price.round(2)} " \
          "(profit: #{(current_profit_pct * 100.0).round(2)}%)"
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

    # Check if tailored trailing is applicable for this position
    def tailored_trailing_applicable?(position_data)
      return false unless position_data.index_key || position_data.security_id

      # Get symbol or index key
      key = position_data.index_key.to_s.upcase
      position_data.security_id.to_s.upcase # security_id often contains the symbol in some contexts, but better check both

      # Use index_key or underlying symbol
      search_key = position_data.underlying_symbol.to_s.upcase.presence || key
      %w[NIFTY BANKNIFTY SENSEX].any? { |s| search_key.include?(s) }
    end

    # Apply tailored trailing SL (Gamma-Aware + MFE approach for indices)
    # rubocop:disable Metrics/AbcSize
    def apply_tailored_sl(position_data, tracker: nil)
      return { updated: false, new_sl_price: nil, reason: 'invalid_position' } unless position_data.valid?

      current_price = position_data.current_ltp.to_f
      current_sl = position_data.sl_price.to_f
      peak_profit_pct = position_data.peak_profit_pct.to_f
      prices = position_data.price_history || [current_price]

      tracker ||= PositionTracker.find_by(id: position_data.tracker_id)
      return { updated: false, new_sl_price: current_sl, reason: 'tracker_not_found' } unless tracker&.active?

      # 1. Use Orders::Analyzer for combined analysis
      analyzer = Orders::Analyzer.new(
        tracker: tracker,
        ltp: current_price,
        prices: prices,
        peak_profit_pct: peak_profit_pct
      )
      new_sl_price = analyzer.recommended_sl

      # 2. Use Orders::Adjuster to decide and execute adjustment
      # Identify reason for logging
      mfe_sl = Orders::MfeExitEngine.new(
        position: tracker,
        ltp: current_price,
        entry_price: position_data.entry_price.to_f,
        highest_price: position_data.entry_price.to_f * (1.0 + peak_profit_pct)
      ).call
      reason_code = mfe_sl && new_sl_price == mfe_sl ? 'mfe_retrace' : 'gamma_aware'

      adjusted = Orders::Adjuster.adjust_sl(
        tracker: tracker,
        recommended_sl: new_sl_price,
        reason: "#{reason_code}_trailing (profit: #{(peak_profit_pct * 100).round(2)}%)"
      )

      if adjusted
        # Update local position_data for the rest of the tick processing
        sl_offset_pct = (new_sl_price - position_data.entry_price.to_f) / position_data.entry_price.to_f
        position_data.sl_price = new_sl_price if position_data.respond_to?(:sl_price=)
        position_data.sl_offset_pct = sl_offset_pct if position_data.respond_to?(:sl_offset_pct=)

        { updated: true, new_sl_price: new_sl_price, reason: 'sl_updated' }
      else
        { updated: false, new_sl_price: current_sl, reason: 'sl_not_improved_or_error' }
      end
    rescue StandardError => e
      Rails.logger.error("[TrailingEngine] Failed to apply tailored SL: #{e.class} - #{e.message}")
      { updated: false, new_sl_price: nil, reason: e.message }
    end
    # rubocop:enable Metrics/AbcSize

    # Build failure result hash
    # @param error [String] Error message
    # @return [Hash]
    def trailing_for(tracker)
      Positions::TrailingConfig.from_tracker(tracker)
    end

    def failure_result(error)
      {
        peak_updated: false,
        sl_updated: false,
        exit_triggered: false,
        error: error
      }
    end

    def peak_drawdown_activation_enabled?
      feature_flags[:enable_peak_drawdown_activation] == true
    end

    def feature_flags
      @feature_flags ||= begin
        AlgoConfig.fetch[:feature_flags] || {}
      rescue StandardError
        {}
      end
    end

    # Returns SL offset as percentage (e.g. 10.0 for 10%) for display/logging
    # Always computed from prices for consistent format (sl_offset_pct storage is mixed decimal/percentage)
    def current_sl_offset_pct(position_data)
      entry = position_data.entry_price.to_f
      sl_price = position_data.sl_price.to_f
      return nil unless entry.positive? && sl_price.positive?

      ((sl_price - entry) / entry) * 100.0
    end

    # Returns SL offset as decimal (e.g. 0.10 for 10%) for TrailingConfig.peak_drawdown_active?
    def current_sl_offset_pct_decimal(position_data)
      entry = position_data.entry_price.to_f
      sl_price = position_data.sl_price.to_f
      return nil unless entry.positive? && sl_price.positive?

      (sl_price - entry) / entry
    end

    def increment_peak_drawdown_metric
      # Track peak-drawdown exits for observability
      # This could be integrated with a metrics service if available
      Rails.logger.info('[TrailingEngine] Peak drawdown exit metric incremented')
    end

    # Calculate capital deployed for a position
    # @param position_data [Positions::ActiveCache::PositionData] Position data
    # @return [Float, nil] Capital deployed (entry_price * quantity) or nil if not available
    def calculate_capital_deployed(position_data)
      return nil unless position_data.entry_price&.positive? && position_data.quantity&.positive?

      position_data.entry_price.to_f * position_data.quantity.to_i
    rescue StandardError
      nil
    end
  end
  # rubocop:enable Metrics/ClassLength
end
