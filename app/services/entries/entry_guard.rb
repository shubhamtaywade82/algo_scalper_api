# frozen_string_literal: true

require_relative '../concerns/broker_fee_calculator'
require_relative 'bos_extractor'

module Entries
  class EntryGuard
    ENTRY_CONTRACT = 'bos_machine_v1'
    SUPERTREND_CONTRACT = 'supertrend_machine_v1'
    BOS_SWING_LOOKBACK = 5
    BOS_MAX_AGE_CANDLES = 8
    BOS_MAX_ENTRY_DELAY_CANDLES = 3
    BOS_MAX_ENTRY_DISTANCE_R = 0.5

    class << self
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil)
        Rails.logger.info("[EntryGuard] Attempting entry for #{index_cfg[:key]} (#{direction})")

        # Circuit breaker — highest priority, checked before everything else
        if Risk::CircuitBreaker.instance.tripped?
          cb = Risk::CircuitBreaker.instance.status
          Rails.logger.error("[EntryGuard] Entry blocked — circuit breaker tripped: #{cb[:reason]} (at: #{cb[:at]})")
          return false
        end

        unless bos_contract_present?(entry_metadata)
Rails.logger.error(
            "[EntryGuard] Direct entry blocked for #{index_cfg[:key]}: BOS contract missing. Metadata: #{entry_metadata.inspect}"
          )
          return false
        end
        Rails.logger.debug "[EntryGuard] Contract check passed for #{index_cfg[:key]}"

        # Time regime validation (session-aware entry rules)
        unless time_regime_allows_entry?(index_cfg: index_cfg, pick: pick, direction: direction)
          Rails.logger.info("[EntryGuard] Entry blocked by time regime rules for #{index_cfg[:key]}")
          return false
        end

        # Edge failure detector (rolling PnL window, consecutive SLs, session-based)
        edge_check = Live::EdgeFailureDetector.instance.entries_paused?(index_key: index_cfg[:key])
        if edge_check[:paused]
          resume_at = edge_check[:resume_at]
          resume_str = resume_at ? resume_at.strftime('%H:%M IST') : 'manual override'
          Rails.logger.info(
            "[EntryGuard] Entry blocked by edge failure detector for #{index_cfg[:key]}: #{edge_check[:reason]} (resume at: #{resume_str})"
          )
          signal&.record_entry_outcome('skipped', 'drawdown_guard_active')
          return false
        end

        # Portfolio-level policy gate (fast fail before building context)
        entry_policy = Policies::EntryPolicy.new(index_cfg: index_cfg, direction: direction)
        unless entry_policy.permitted?
          Rails.logger.info("[EntryGuard] EntryPolicy blocked — #{entry_policy.reasons.join(', ')}")
          return false
        end

        context = {
          index_cfg: index_cfg,
          pick: pick,
          direction: direction,
          scale_multiplier: scale_multiplier,
          entry_metadata: entry_metadata,
          permission: permission
        }
        result = entry_guard_pipeline.run(context)
        if result != EntryGuardPipeline::PASS
          reason = result.is_a?(Hash) ? result[:blocked] : result.to_s
          Rails.logger.info("[EntryGuard] Entry blocked — #{reason}")
          return false
        end

        multiplier = [scale_multiplier.to_i, 1].max
        Rails.logger.info("[EntryGuard] Scale multiplier for #{index_cfg[:key]}: x#{multiplier}") if multiplier > 1

        side = direction == :bullish ? 'long_ce' : 'long_pe'
        is_supertrend = entry_metadata&.dig(:entry_contract).to_s == SUPERTREND_CONTRACT

        # Exposure check for Supertrend: Allow only ONE active position per index to prevent over-trading
        if is_supertrend
          active_idx_pos = PositionTracker.active.where("(meta->>'index_key') = ?", index_cfg[:key].to_s).exists?
          if active_idx_pos
            Rails.logger.debug { "[EntryGuard] Supertrend exposure check failed: Active position already exists for #{index_cfg[:key]}" }
            return false
          end
        elsif !exposure_ok?(instrument: instrument, side: side, max_same_side: index_cfg[:max_same_side])
          Rails.logger.debug { "[EntryGuard] Exposure check failed for #{index_cfg[:key]}: #{pick[:symbol]} (side: #{side}, max_same_side: #{index_cfg[:max_same_side]})" }
          return false
        end

        if cooldown_active?(pick[:symbol], index_cfg[:cooldown_sec].to_i)
          Rails.logger.warn("[EntryGuard] Cooldown active for #{index_cfg[:key]}: #{pick[:symbol]}")
          return false
        end
        unless bos_context
          signal&.record_entry_outcome('blocked', 'bos_structure_gate')
          return false
        end

    class << self
      include Live::UnderlyingLtpResolver

        # ===== Unified instrument profile + capital cap sizing (hard rules) =====
        symbol = index_cfg[:key].to_s.upcase
        permission_sym = (permission || entry_metadata&.dig(:permission) || :scale_ready).to_s.downcase.to_sym

        # Weekly expiry only (hard rule) - block monthly contracts for NIFTY/SENSEX.
        if %w[NIFTY SENSEX].include?(symbol) && !weekly_contract?(pick: pick, index_cfg: index_cfg)
          Rails.logger.info("[EntryGuard] Weekly-only expiry rule blocked #{symbol} entry for #{pick[:symbol]}")
          return false
        end

        profile = Trading::InstrumentExecutionProfile.for(symbol)

        if permission_sym == :execution_only && profile[:allow_execution_only] == false
          Rails.logger.info("[EntryGuard] Execution-only blocked for #{symbol} by profile")
          return false
        end

        permission_cap = profile[:max_lots_by_permission][permission_sym].to_i
        lot_size = Trading::LotCalculator.lot_size_for(symbol)

        cap_lots = Trading::CapitalAllocator.max_lots(
          premium: ltp.to_f,
          lot_size: lot_size,
          permission_cap: permission_cap
        )

        if cap_lots <= 0
          Rails.logger.info(
            "[EntryGuard] Trade blocked by sizing for #{symbol}: permission=#{permission_sym}, " \
            "permission_cap=#{permission_cap}, lot_size=#{lot_size}, premium=#{ltp}"
          )
          signal&.record_entry_outcome('blocked', 'reentry_cooldown')
          return false
        end

        if entry_metadata&.dig(:entry_contract).to_s == SUPERTREND_CONTRACT
          # Bypass BOS gate for Supertrend-only mode
          bos_context = {
            confirmed_at: Time.current,
            confirmed_index: -1,
            direction: direction,
            bos_id: entry_metadata[:bos_id],
            timeframe: entry_metadata[:bos_timeframe],
            origin_swing: { price: entry_metadata[:bos_origin_price] },
            broken_swing: { price: entry_metadata[:bos_level] },
            entry_underlying_price: ltp.to_f
          }
        else
          bos_context = enforce_structure_entry_gate(
            index_cfg: index_cfg,
            instrument: instrument,
            direction: direction,
            entry_price: ltp.to_f,
            entry_metadata: entry_metadata
          )
        end
        return false unless bos_context

        # ===== Unified instrument profile + capital cap sizing (hard rules) =====
        symbol = index_cfg[:key].to_s.upcase
        permission_sym = (permission || entry_metadata&.dig(:permission) || :scale_ready).to_s.downcase.to_sym

        # Weekly expiry only (hard rule) - block monthly contracts for NIFTY/SENSEX.
        # Bypass for Supertrend testing mode.
        if !is_supertrend && %w[NIFTY SENSEX].include?(symbol) && !weekly_contract?(pick: pick, index_cfg: index_cfg)
          Rails.logger.info("[EntryGuard] Weekly-only expiry rule blocked #{symbol} entry for #{pick[:symbol]}")
          signal&.record_entry_outcome('blocked', 'weekly_only_expiry_rule')
          return false
        end

        profile = Trading::InstrumentExecutionProfile.for(symbol)

        if permission_sym == :execution_only && profile[:allow_execution_only] == false
          Rails.logger.info("[EntryGuard] Execution-only blocked for #{symbol} by profile")
          signal&.record_entry_outcome('blocked', 'execution_only_blocked_by_profile')
          return false
        end

        permission_cap = profile[:max_lots_by_permission][permission_sym].to_i
        lot_size = Trading::LotCalculator.lot_size_for(symbol)

        cap_lots = Trading::CapitalAllocator.max_lots(
          premium: ltp.to_f,
          lot_size: lot_size,
          permission_cap: permission_cap
        )

        if cap_lots <= 0
          Rails.logger.info(
            "[EntryGuard] Trade blocked by sizing for #{symbol}: permission=#{permission_sym}, permission_cap=#{permission_cap}, lot_size=#{lot_size}, premium=#{ltp}"
          )
          signal&.record_entry_outcome('blocked', 'capital_sizing_cap_zero')
          return false
        end
        Rails.logger.debug "[EntryGuard] Sizing check passed: #{cap_lots} lots"

        quantity_by_existing_allocator = Capital::Allocator.qty_for(
          index_cfg: index_cfg,
          entry_price: ltp.to_f,
          derivative_lot_size: lot_size,
          scale_multiplier: multiplier
        )

        quantity_by_cap = cap_lots * lot_size
        quantity = [quantity_by_existing_allocator.to_i, quantity_by_cap.to_i].min
        quantity = (quantity / lot_size) * lot_size # ensure lot-aligned

        if quantity <= 0 || quantity < lot_size
          Rails.logger.warn(
            "[EntryGuard] Quantity blocked for #{index_cfg[:key]}: #{pick[:symbol]} (qty=#{quantity}, cap_qty=#{quantity_by_cap}, alloc_qty=#{quantity_by_existing_allocator}, lot_size=#{lot_size}, ltp=#{ltp})"
          )
          signal&.record_entry_outcome('blocked', 'quantity_below_lot_minimum')
          return false
        end

        response = Orders.config.gateway.place_market(
          side: 'buy',
          segment: pick[:segment] || index_cfg[:segment],
          security_id: pick[:security_id],
          qty: quantity,
          meta: {
            client_order_id: build_client_order_id(index_cfg: index_cfg, pick: pick),
            ltp: ltp,
            price: ltp,
            symbol: pick[:symbol]
          }
        ).call

        unless place_cmd.success?
          Rails.logger.error("[EntryGuard] place_market failed for #{index_cfg[:key]}: #{pick[:symbol]} (#{place_cmd.reason})")
          return false
        end

        if response.is_a?(Hash) && response[:success] == false
          Rails.logger.error("[EntryGuard] place_market failed for #{index_cfg[:key]}: #{pick[:symbol]} (response: #{response.inspect})")
          return false
        end

        order_no = extract_order_no(response)
        unless order_no
          Rails.logger.warn("[EntryGuard] Order placement failed for #{index_cfg[:key]}: #{pick[:symbol]} (response: #{response.inspect})")
          Observability::StructuredLog.warn(
            event: 'entry_order_missing_order_no',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s
            }
          )
          signal&.record_entry_outcome('blocked', 'order_no_missing')
          return false
        end

        tracker = if response.is_a?(Hash) && response[:paper]
                    create_paper_tracker!(
                      instrument: instrument,
                      pick: pick,
                      side: side,
                      quantity: quantity,
                      index_cfg: index_cfg,
                      ltp: ltp,
                      order_no: order_no,
                      entry_metadata: entry_metadata,
                      bos_context: bos_context
                    )
                  else
                    create_tracker!(
                      instrument: instrument,
                      order_no: order_no,
                      pick: pick,
                      side: side,
                      quantity: quantity,
                      index_cfg: index_cfg,
                      ltp: ltp,
                      entry_metadata: entry_metadata,
                      bos_context: bos_context
                    )
                  end

        mark_bos_consumed!(index_cfg: index_cfg, bos_context: bos_context) if tracker

        Rails.logger.info("[EntryGuard] Successfully placed order #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]}")
        !!tracker
      rescue StandardError => e
        signal&.record_entry_outcome('blocked', "exception: #{e.class}")
        Rails.logger.error("EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
        Observability::StructuredLog.error(
          event: 'entry_guard_exception',
          payload: {
            service: 'Entries::EntryGuard',
            index_key: index_cfg[:key].to_s,
            symbol: pick[:symbol].to_s,
            error_class: e.class.to_s,
            error_message: e.message
          }
        )
        false
      end

      def exposure_ok?(instrument:, side:, max_same_side:)
        max_allowed = max_same_side.to_i

        # Safety check: if max_same_side is not configured (nil or 0), default to 1
        if max_allowed <= 0
          Rails.logger.warn("[EntryGuard] Invalid max_same_side value: #{max_same_side.inspect}, defaulting to 1")
          max_allowed = 1
        end

        # Check positions by underlying instrument (for derivatives, check their underlying instrument)
        # This ensures all positions on the same index count together, regardless of strike
        # Query by instrument_id (for direct positions) OR by watchable_type='Derivative' with instrument_id
        active_positions = PositionTracker.active.where(side: side).where(
          "(instrument_id = ? OR (watchable_type = 'Derivative' AND watchable_id IN (SELECT id FROM derivatives WHERE instrument_id = ?)))",
          instrument.id, instrument.id
        ).limit(max_allowed + 1)
        current_count = active_positions.count

        Rails.logger.debug { "[EntryGuard] Exposure check for #{instrument.symbol_name}: side=#{side}, current=#{current_count}, max=#{max_allowed}" }

        # Check if we've reached the maximum allowed positions
        if current_count >= max_allowed
          Rails.logger.warn("[EntryGuard] Exposure limit reached for #{instrument.symbol_name}: #{current_count} >= #{max_allowed} (side: #{side})")
          return false
        end

        # Success - Tracker created
        signal&.record_entry_outcome('entered')
        validate_entry_price!(execution_result, context)
        true
      end

      def pyramiding_allowed?(first_position)
        # AGGRESSIVE MODE: Allow pyramiding immediately without profit requirement
        # Reduced profit duration from 5 minutes to 30 seconds for aggressive entries
        min_profit_duration = 30.seconds

        # Allow pyramiding if:
        # 1. Position is profitable (even slightly), OR
        # 2. Position has been open for at least 30 seconds (reduced from 5 minutes)
        if first_position.last_pnl_rupees&.positive?
          Rails.logger.info("[Pyramiding] Allowing second position - first position profitable: ₹#{first_position.last_pnl_rupees.round(2)}")
          return true
        end

        # Allow if position has been open for minimum duration (aggressive mode)
        if first_position.updated_at < min_profit_duration.ago
          Rails.logger.info("[Pyramiding] Allowing second position - first position open for #{min_profit_duration} seconds")
          return true
        end

        false
      rescue StandardError => e
        Rails.logger.error("Pyramiding check failed: #{e.message}")
        # In aggressive mode, allow on error to avoid blocking
        true
      end

      # Used by OrderExecutionService
      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata:, bos_context:)
        PositionTracker.transaction do
          meta_hash = build_base_meta(index_cfg: index_cfg, pick: pick, direction: bos_context&.dig(:direction))
          apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        snapshot = meta_hash.delete('config_snapshot')
        version = meta_hash.delete('config_version') || {}
        entry_at = meta_hash.delete('entry_at')

        tracker_attrs, legacy_meta = split_meta_hash(meta_hash)

        tracker = PositionTracker.create!(
          order_no: order_no,
          instrument: instrument,
          watchable: instrument,
          security_id: pick[:security_id],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          symbol: pick[:symbol],
          status: :active,
          paper: false,
          **tracker_attrs,
          meta: legacy_meta
        )

        tracker.create_position_meta_snapshot!(
          config_version_hash: version['hash'].to_s,
          config_change_log_id: version['change_log_id'],
          config_snapshot: snapshot,
          entry_at: entry_at
        )

        tracker
      end

      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:, order_no:, entry_metadata:, bos_context:)
        PositionTracker.transaction do
          meta_hash = build_base_meta(index_cfg: index_cfg, pick: pick, direction: bos_context&.dig(:direction))
          apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        snapshot = meta_hash.delete('config_snapshot')
        version = meta_hash.delete('config_version') || {}
        entry_at = meta_hash.delete('entry_at')

        tracker_attrs, legacy_meta = split_meta_hash(meta_hash)

        tracker = PositionTracker.create!(
          order_no: order_no,
          instrument: instrument,
          watchable: instrument,
          security_id: pick[:security_id],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          symbol: pick[:symbol],
          status: :active,
          paper: true,
          **tracker_attrs,
          meta: legacy_meta
        )
        tracker.create_position_meta_snapshot!(
          config_version_hash: version['hash'].to_s,
          config_change_log_id: version['change_log_id'],
          config_snapshot: snapshot
        )

        # For live positions, try to get from Redis PnL cache first (has pre-calculated PnL)
        # Then fall back to calculating from tick data
        pnl_cache = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
        if pnl_cache && pnl_cache[:pnl]
          # Use pre-calculated PnL from Redis
          tracker.update!(
            last_pnl_rupees: BigDecimal(pnl_cache[:pnl].to_s),
            last_pnl_pct: pnl_cache[:pnl_pct] ? BigDecimal(pnl_cache[:pnl_pct].to_s) : nil,
            high_water_mark_pnl: pnl_cache[:hwm_pnl] ? BigDecimal(pnl_cache[:hwm_pnl].to_s) : tracker.high_water_mark_pnl
          )
          Rails.logger.debug { "[EntryGuard] Loaded PnL from Redis cache for #{tracker.order_no}: PnL=₹#{pnl_cache[:pnl].round(2)}" }
          return
        end

        # Fallback: Calculate from tick data if Redis PnL cache is empty
        segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
        security_id = tracker.security_id
        return unless segment.present? && security_id.present?

        # Try Redis tick cache
        tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
        if tick
          ltp = tick.ltp
          entry = BigDecimal(tracker.entry_price.to_s)
          qty = tracker.quantity.to_i
          pnl = (ltp - entry) * qty
          # Calculate pnl_pct as decimal (0.0573 for 5.73%) for consistent storage (matches Redis format)
          pnl_pct = entry.positive? ? ((ltp - entry) / entry) : nil

          hwm = tracker.high_water_mark_pnl || BigDecimal(0)
          hwm = [hwm, pnl].max

          tracker.update!(
            last_pnl_rupees: pnl,
            last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil,
            high_water_mark_pnl: hwm
          )
          Rails.logger.debug { "[EntryGuard] Calculated PnL from tick data for #{tracker.order_no}: PnL=₹#{pnl.round(2)}" }
        end
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Failed to calculate PnL for #{tracker.order_no}: #{e.message}")
      end

      def build_client_order_id(index_cfg:, pick:)
        "#{index_cfg[:key]}_#{pick[:symbol]}_#{Time.current.to_i}"
      end

        # Try WebSocket cache first
        tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
        return tick.ltp if tick

        return false unless derivative

        flag = derivative.expiry_flag.to_s.upcase
        flag.start_with?('W') # WEEK / WEEKLY
      rescue StandardError => e
        Rails.logger.warn("[EntryGuard] Weekly contract check failed: #{e.class} - #{e.message}")
        false
      end

      def cooldown_active_for_index?(index_key, cooldown)
        return false if index_key.blank? || cooldown <= 0

        last = Rails.cache.read("reentry:index:#{index_key}")
        last.present? && (Time.current - last) < cooldown
      end

      # BANKNIFTY trades only in the last week before monthly expiry (last Thursday of month).
      # Returns true if today is within 7 calendar days of the last Thursday.
      def banknifty_last_week?
        today    = Time.zone.today
        last_day = today.end_of_month
        last_thu = last_day - ((last_day.wday - 4) % 7).days
        # If last_thu falls before today (we've passed expiry this month), check next month
        if last_thu < today
          last_day = (today + 1.month).end_of_month
          last_thu = last_day - ((last_day.wday - 4) % 7).days
        end
        (last_thu - today).to_i.between?(0, 6)
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] banknifty_last_week? error: #{e.message}")
        false
      end

      def weekly_contract?(pick:, index_cfg:)
        # Prefer derivative_id if present
        derivative =
          if pick[:derivative_id].present?
            Derivative.find_by(id: pick[:derivative_id])
          else
            Derivative.find_by(
              security_id: pick[:security_id].to_s,
              segment: (pick[:segment] || index_cfg[:segment]).to_s
            )
          end

        return false unless derivative

        flag = derivative.expiry_flag.to_s.upcase
        flag.start_with?('W') # WEEK / WEEKLY
      rescue StandardError => e
        Rails.logger.warn("[EntryGuard] Weekly contract check failed: #{e.class} - #{e.message}")
        false
      end

      # Checks if we need to fetch LTP from REST API
      # @param pick [Hash] Pick data from signal
      # @return [Boolean]
      def needs_api_ltp?(pick)
        hub = Live::MarketFeedHub.instance
        return true unless hub.running? && hub.connected?

        last = Rails.cache.read("reentry:index:#{index_key}")
        last.present? && (Time.current - last) < cooldown
      end

      # BANKNIFTY trades only in the last week before monthly expiry.
      # Uses instrument expiry_list to find the actual monthly expiry date (holiday-aware).
      # Falls back to last-Thursday-of-month calculation only when expiry_list is unavailable.
      # Returns true if today is within 7 calendar days of the nearest upcoming monthly expiry.
      def banknifty_last_week?(instrument: nil)
        today          = Time.zone.today
        monthly_expiry = banknifty_monthly_expiry(instrument, today)
        return false unless monthly_expiry

        days_to_expiry = (monthly_expiry - today).to_i
        days_to_expiry.between?(0, 6)
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] banknifty_last_week? error: #{e.message}")
        false
      end

      def extract_order_no(response)
        Ledger::OrderResponse.extract_order_id(response) || legacy_extract_order_no(response)
      end

        # Strategy 1: WebSocket subscription + TickCache (fastest, no API rate limits)
        if hub.running? && hub.connected?
          # Subscribe to the strike/derivative immediately
          begin
            hub.subscribe(segment: segment, security_id: security_id)
            Rails.logger.debug { "[EntryGuard] Subscribed to #{segment}:#{security_id} for LTP resolution" }

            # Wait briefly for tick to arrive (typically < 100ms)
            max_wait_ms = 300
            poll_interval_ms = 50
            attempts = (max_wait_ms / poll_interval_ms).to_i

            attempts.times do
              cached_tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
              if cached_tick&.ltp&.to_f&.positive?
                Rails.logger.debug { "[EntryGuard] Got LTP from TickCache for #{segment}:#{security_id}: ₹#{cached_tick.ltp}" }
                return cached_tick.ltp
              end
              sleep(poll_interval_ms / 1000.0) # Convert ms to seconds
            end

        response
      end

      def timeframe_to_interval(timeframe)
        return nil if timeframe.blank?
        str = timeframe.to_s.strip.downcase
        return nil if str.empty?
        if str.end_with?('h')
          hours = str.gsub(/[^0-9]/, '').to_i
          return nil if hours <= 0
          return hours * 60
        end
        str.gsub(/[^0-9]/, '').to_i
      end

      # Check if daily loss/profit limits allow entry (NOT trade frequency - we don't cap trade count)
      def daily_limits_allow_entry?(index_cfg:)
        return true unless daily_limits_enabled?

        daily_limits = Live::DailyLimits.new
        result = daily_limits.can_trade?(index_key: index_cfg[:key])

        unless result[:allowed]
          reason = result[:reason]
          # Only block on loss/profit limits, NOT trade frequency limits
          case reason
          when 'trade_frequency_limit_exceeded', 'global_trade_frequency_limit_exceeded'
            # Ignore trade frequency limits - we don't cap trade count
            return true
          when 'daily_loss_limit_exceeded'
            Rails.logger.warn(
              "[EntryGuard] Daily loss limit exceeded for #{index_cfg[:key]}: ₹#{result[:daily_loss].round(2)}/₹#{result[:max_daily_loss]}"
            )
            return false
          when 'global_daily_loss_limit_exceeded'
            Rails.logger.warn(
              "[EntryGuard] Global daily loss limit exceeded: ₹#{result[:global_daily_loss].round(2)}/₹#{result[:max_global_loss]}"
            )
            return false
          when 'daily_profit_target_reached'
            Rails.logger.info(
              "[EntryGuard] Daily profit target reached: ₹#{result[:global_daily_profit].round(2)}/₹#{result[:max_daily_profit]}"
            )
            return false
          end
          return false
        end

        true
      rescue StandardError => e
        Rails.logger.warn("[EntryGuard] validate_entry_price! failed: #{e.class} - #{e.message}")
      end

      private

      def banknifty_monthly_expiry(instrument, today)
        expiry_list = instrument&.expiry_list&.compact
        if expiry_list.present?
          parsed = expiry_list.filter_map do |raw|
            case raw
            when Date then raw
            when String
              begin
                Date.parse(raw)
              rescue ArgumentError, TypeError
                nil
              end
            when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
            end
          end.sort

          monthly_expiries = parsed.group_by { |d| [d.year, d.month] }
                                   .map { |_, dates| dates.max }
                                   .sort

          nearest = monthly_expiries.find { |d| d >= today }
          return nearest if nearest
        end

        # Fallback: last Thursday of month
        last_day = today.end_of_month
        last_thu = last_day - ((last_day.wday - 4) % 7).days
        if last_thu < today
          last_day = (today + 1.month).end_of_month
          last_thu = last_day - ((last_day.wday - 4) % 7).days
        end
        last_thu
      end

      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:, order_no:, entry_metadata: nil, bos_context: nil)

        # Determine watchable: derivative for options, instrument for indices
        watchable = find_watchable_for_pick(pick: pick, instrument: instrument)

        # Build meta hash with entry strategy/path information
        meta_hash = {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current,
          paper_trading: true
        }

        # Add diagnostic metadata if provided
        merge_diagnostic_metadata!(meta_hash, entry_metadata) if entry_metadata.is_a?(Hash)

        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        tracker = PositionTracker.create!(
          watchable: watchable,
          instrument: watchable.is_a?(Derivative) ? watchable.instrument : watchable, # Backward compatibility
          order_no: order_no,
          security_id: pick[:security_id].to_s,
          symbol: pick[:symbol],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: 'active',
          paper: true,
          meta: meta_hash,
          trade_state: 'init'
        )

        # Subscription is handled automatically by after_create_commit :subscribe_to_feed callback
        # No need to call tracker.subscribe explicitly

        # Initialize PnL in Redis (will be 0 initially since entry_price = ltp)
        # This ensures the position is tracked in Redis from the start
        initial_pnl = BigDecimal(0)
        Live::RedisPnlCache.instance.store_pnl(
          tracker_id: tracker.id,
          pnl: initial_pnl,
          pnl_pct: 0.0,
          ltp: ltp,
          hwm: initial_pnl,
          timestamp: Time.current
        )

        Rails.logger.info("[EntryGuard] Paper trading: Created position #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]} (qty: #{quantity}, entry: ₹#{ltp}, watchable: #{watchable.class.name})")
        tracker
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist paper tracker: #{e.record.errors.full_messages.to_sentence}")
        false
      end

      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata: nil, bos_context: nil)
        # Determine watchable: derivative for options, instrument for indices
        watchable = find_watchable_for_pick(pick: pick, instrument: instrument)

        # Build meta hash with entry strategy/path information
        meta_hash = {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current
        }

        # Add diagnostic metadata if provided
        merge_diagnostic_metadata!(meta_hash, entry_metadata) if entry_metadata.is_a?(Hash)

        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        PositionTracker.build_or_average!(
          watchable: watchable,
          instrument: watchable.is_a?(Derivative) ? watchable.instrument : watchable, # Backward compatibility
          order_no: order_no,
          security_id: pick[:security_id].to_s,
          symbol: pick[:symbol],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          meta: meta_hash,
          trade_state: 'init'
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist tracker for order #{order_no}: #{e.record.errors.full_messages.to_sentence}")
      end

      def enforce_structure_entry_gate(index_cfg:, instrument:, direction:, entry_price:, entry_metadata:)
        timeframe = effective_timeframe(entry_metadata)
        unless timeframe
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: missing effective_timeframe")
          return nil
        end

        interval = timeframe_to_interval(timeframe)
        unless interval
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: invalid timeframe #{timeframe}")
          return nil
        end

        series = instrument.candle_series(interval: interval)
        unless series&.candles&.any?
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: no candle series for #{timeframe}")
          return nil
        end

        bos = Entries::BosExtractor.last_confirmed_bos(series, lookback: BOS_SWING_LOOKBACK)
        unless bos
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: no confirmed BOS (#{timeframe})")
          return nil
        end

        if bos[:direction] != direction
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: BOS direction #{bos[:direction]} != entry #{direction}")
          return nil
        end

        last_idx = series.candles.size - 1
        bos_age = last_idx - bos[:confirmed_index]
        if bos_age > BOS_MAX_AGE_CANDLES
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: BOS stale (age=#{bos_age} candles)")
          return nil
        end

        if bos_age > BOS_MAX_ENTRY_DELAY_CANDLES
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: entry delay too late (delay=#{bos_age} candles)")
          return nil
        end

        origin_price = bos[:origin_swing][:price].to_f
        broken_price = bos[:broken_swing][:price].to_f
        risk_points = (broken_price - origin_price).abs
        if risk_points <= 0
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: invalid BOS risk_points=#{risk_points}")
          return nil
        end

        entry_underlying_price = series.candles.last&.close
        unless entry_underlying_price
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: missing underlying close for entry")
          return nil
        end

        entry_distance_r = (entry_underlying_price.to_f - origin_price).abs / risk_points
        if entry_distance_r > BOS_MAX_ENTRY_DISTANCE_R
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: entry_distance_r=#{entry_distance_r.round(2)} > #{BOS_MAX_ENTRY_DISTANCE_R}")
          return nil
        end

        bos_id = Entries::BosExtractor.bos_id(timeframe: timeframe, confirmed_at: bos[:confirmed_at], direction: bos[:direction])
        metadata_bos_id = entry_metadata.is_a?(Hash) ? entry_metadata[:bos_id] : nil
        if metadata_bos_id.present? && metadata_bos_id.to_s != bos_id.to_s
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: BOS id mismatch (meta=#{metadata_bos_id}, calc=#{bos_id})")
          return nil
        end

        metadata_bos_tf = entry_metadata.is_a?(Hash) ? entry_metadata[:bos_timeframe] : nil
        if metadata_bos_tf.present? && metadata_bos_tf.to_s != timeframe.to_s
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: BOS timeframe mismatch (meta=#{metadata_bos_tf}, calc=#{timeframe})")
          return nil
        end

        if bos_consumed?(index_cfg: index_cfg, bos_id: bos_id)
          Rails.logger.info("[EntryGuard] BOS gate blocked #{index_cfg[:key]}: BOS already consumed (#{bos_id})")
          return nil
        end

        bos.merge(
          timeframe: timeframe,
          bos_id: bos_id,
          entry_distance_r: entry_distance_r,
          risk_points: risk_points,
          entry_underlying_price: entry_underlying_price
        )
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] BOS gate failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
        nil
      end

      def apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price:, quantity:)
        return unless bos_context

        contract = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_contract].to_s : ''
        if contract == SUPERTREND_CONTRACT
          # Supertrend direct entries do not have BOS structure risk; derive premium risk from configured SL %.
          sl_decimal = supertrend_sl_decimal
          premium_r = entry_price.to_f * sl_decimal
          entry_risk_rupees = premium_r * quantity.to_i
          origin_price = nil # No BOS swing level; structure invalidation must use underlying at entry
          entry_underlying_price = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_underlying_price] : nil
        else
          origin_price = bos_context[:origin_swing][:price].to_f
          entry_underlying_price = bos_context[:entry_underlying_price]
          sl_decimal = supertrend_sl_decimal
          premium_r = entry_price.to_f * sl_decimal
          entry_risk_rupees = premium_r * quantity.to_i
        end
        premium_stop = entry_price.to_f - premium_r
        premium_target = entry_price.to_f + premium_r

        # Structure invalidation must be in UNDERLYING domain (index level). Never use option premium.
        # For BOS entries we use origin_swing price (underlying). For supertrend we omit so only the
        # 5m/15m candle-based rule runs (avoids tick-noise exits and reduces brokerage from quick flips).
        meta_hash[:structure_invalidation_price] = origin_price if origin_price.present?
        meta_hash[:entry_premium] = entry_price.to_f
        meta_hash[:peak_premium] = entry_price.to_f
        meta_hash[:peak_premium_at] = Time.current.iso8601
        meta_hash[:entry_risk_rupees] = entry_risk_rupees
        meta_hash[:premium_stop_price] = premium_stop
        meta_hash[:premium_target_price] = premium_target
        meta_hash[:entry_underlying_price] = entry_underlying_price if entry_underlying_price
        meta_hash[:bos_confirmed_at] = bos_context[:confirmed_at]&.iso8601
        meta_hash[:bos_origin_index] = bos_context[:origin_swing][:index]
        meta_hash[:bos_timeframe] = bos_context[:timeframe]
        meta_hash[:bos_direction] = bos_context[:direction]
        meta_hash[:bos_id] = bos_context[:bos_id]

        if entry_metadata.is_a?(Hash)
          meta_hash[:bos_age_at_entry] = entry_metadata[:bos_age_at_entry] if entry_metadata.key?(:bos_age_at_entry)
          meta_hash[:retrace_pct] = entry_metadata[:retrace_pct] if entry_metadata.key?(:retrace_pct)
          meta_hash[:pullback_candles] = entry_metadata[:pullback_candles] if entry_metadata.key?(:pullback_candles)
          meta_hash[:entry_distance_r] = entry_metadata[:entry_distance_r] if entry_metadata.key?(:entry_distance_r)
          meta_hash[:continuation_body_position] =
            entry_metadata[:continuation_body_position] if entry_metadata.key?(:continuation_body_position)
          meta_hash[:time_from_bos_to_entry] =
            entry_metadata[:time_from_bos_to_entry] if entry_metadata.key?(:time_from_bos_to_entry)
          meta_hash[:entry_tf] = entry_metadata[:entry_tf] if entry_metadata.key?(:entry_tf)
          meta_hash[:htf_tf] = entry_metadata[:htf_tf] if entry_metadata.key?(:htf_tf)
        end
      end

      def bos_consumed?(index_cfg:, bos_id:)
        Rails.cache.read(bos_consumed_key(index_cfg: index_cfg, bos_id: bos_id)) == true
      rescue StandardError
        false
      end

      def mark_bos_consumed!(index_cfg:, bos_context:)
        return unless bos_context

        Rails.cache.write(
          bos_consumed_key(index_cfg: index_cfg, bos_id: bos_context[:bos_id]),
          true,
          expires_in: 1.day
        )
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Failed to mark BOS consumed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
      end

      def bos_consumed_key(index_cfg:, bos_id:)
        "bos:consumed:#{index_cfg[:key]}:#{bos_id}"
      end

      def effective_timeframe(entry_metadata)
        return nil unless entry_metadata.is_a?(Hash)

        entry_metadata[:effective_timeframe] || entry_metadata[:primary_timeframe]
      end

      def bos_contract_present?(entry_metadata)
        return false unless entry_metadata.is_a?(Hash)
        contract = entry_metadata[:entry_contract].to_s
        return false unless [ENTRY_CONTRACT, SUPERTREND_CONTRACT].include?(contract)
        return false if entry_metadata[:bos_id].blank?
        return false if entry_metadata[:bos_timeframe].blank?
        return false if entry_metadata[:bos_origin_price].blank?
        return false if entry_metadata[:bos_level].blank?

        true
      end

      def timeframe_to_interval(timeframe)
        return nil if timeframe.blank?

        str = timeframe.to_s.strip.downcase
        return nil if str.empty?

        if str.end_with?('h')
          hours = str.gsub(/[^0-9]/, '').to_i
          return nil if hours <= 0

          (hours * 60).to_s
        else
          minutes = str.gsub(/[^0-9]/, '').to_i
          return nil if minutes <= 0

          minutes.to_s
        end
      end

      def find_watchable_for_pick(pick:, instrument:)
        # If derivative_id is provided in pick, use it
        if pick[:derivative_id].present?
          derivative = Derivative.find_by(id: pick[:derivative_id])
          return derivative if derivative
        end

        # Try to find derivative by security_id and segment
        segment = pick[:segment] || instrument.exchange_segment
        if segment.present? && pick[:security_id].present?
          derivative = Derivative.find_by(
            security_id: pick[:security_id].to_s,
            exchange: instrument.exchange,
            segment: segment
          )
          return derivative if derivative
        end

        [promoted, legacy]
      end
      def merge_diagnostic_metadata!(meta_hash, entry_metadata)
        # Preserve all incoming diagnostic keys from Signal::Engine
        diagnostic_keys = %i[
          regime regime_confidence regime_metrics
          ta_signal ta_confidence ta_bias
          mtf_rsi mtf_macd mtf_atr
          entry_path strategy strategy_mode
          primary_timeframe effective_timeframe
          confirmation_timeframe confirmation_enabled confirmation_direction
          validation_mode validation_passed
          state_count state_multiplier original_timeframe
          smc_decision smc_permission
        ]
        diagnostic_keys.each do |key|
          meta_hash[key] = entry_metadata[key] if entry_metadata.key?(key)
        end

        # Consistency aliases for existing dashboard displays
        meta_hash[:entry_strategy] ||= entry_metadata[:strategy]
        meta_hash[:entry_strategy_mode] ||= entry_metadata[:strategy_mode]
        meta_hash[:entry_timeframe] ||= entry_metadata[:effective_timeframe] || entry_metadata[:primary_timeframe]
        if entry_metadata[:confirmation_timeframe]
          meta_hash[:entry_confirmation_timeframe] = entry_metadata[:confirmation_timeframe]
        end
        meta_hash[:entry_validation_mode] ||= entry_metadata[:validation_mode]
      end

      def split_meta_hash(meta_hash)
        promoted = {}
        legacy = {}

        meta_hash.each do |key, val|
          str_key = key.to_s
          if PositionTracker::PROMOTED_META_KEYS.include?(str_key)
            promoted[str_key] = val
          else
            legacy[key] = val
          end
        end

        [promoted, legacy]
      end
    end
  end
end
