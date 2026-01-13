# frozen_string_literal: true

require_relative '../concerns/broker_fee_calculator'

module Entries
  class EntryGuard
    class << self
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil)
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
            "[EntryGuard] Entry blocked by edge failure detector for #{index_cfg[:key]}: " \
            "#{edge_check[:reason]} (resume at: #{resume_str})"
          )
          return false
        end

        # Daily loss/profit limits check (NOT trade frequency - we don't cap trade count)
        unless daily_limits_allow_entry?(index_cfg: index_cfg)
          Rails.logger.info("[EntryGuard] Entry blocked by daily loss/profit limits for #{index_cfg[:key]}")
          return false
        end

        instrument = find_instrument(index_cfg)
        unless instrument
          Rails.logger.warn("[EntryGuard] Instrument not found for #{index_cfg[:key]} (segment: #{index_cfg[:segment]}, sid: #{index_cfg[:sid]})")
          return false
        end

        multiplier = [scale_multiplier.to_i, 1].max
        Rails.logger.info("[EntryGuard] Scale multiplier for #{index_cfg[:key]}: x#{multiplier}") if multiplier > 1

        side = direction == :bullish ? 'long_ce' : 'long_pe'
        unless exposure_ok?(instrument: instrument, side: side, max_same_side: index_cfg[:max_same_side])
          Rails.logger.debug { "[EntryGuard] Exposure check failed for #{index_cfg[:key]}: #{pick[:symbol]} (side: #{side}, max_same_side: #{index_cfg[:max_same_side]})" }
          return false
        end

        if cooldown_active?(pick[:symbol], index_cfg[:cooldown_sec].to_i)
          Rails.logger.warn("[EntryGuard] Cooldown active for #{index_cfg[:key]}: #{pick[:symbol]}")
          return false
        end

        # Never block due to WebSocket - always allow REST API fallback
        # Log WebSocket status for monitoring but don't block
        hub = Live::MarketFeedHub.instance
        unless hub.running? && hub.connected?
          Rails.logger.info('[EntryGuard] WebSocket not connected - will use REST API fallback for LTP')
        end

        # Rails.logger.debug { "[EntryGuard] Pick data: #{pick.inspect}" }
        # Resolve LTP with REST API fallback if WebSocket unavailable
        ltp = pick[:ltp]
        if ltp.blank? || needs_api_ltp?(pick)
          # Fetch fresh LTP from REST API when WS unavailable or pick LTP is stale
          resolved_ltp = resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg)
          ltp = resolved_ltp if resolved_ltp.present?
        end

        unless ltp.present? && ltp.to_f.positive?
          Rails.logger.warn("[EntryGuard] Invalid LTP for #{index_cfg[:key]}: #{pick[:symbol]} (ltp: #{ltp.inspect})")
          return false
        end

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
          return false
        end

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
            "[EntryGuard] Quantity blocked for #{index_cfg[:key]}: #{pick[:symbol]} " \
            "(qty=#{quantity}, cap_qty=#{quantity_by_cap}, alloc_qty=#{quantity_by_existing_allocator}, lot_size=#{lot_size}, ltp=#{ltp})"
          )
          return false
        end

        # Paper trading mode: Skip real order placement, create PositionTracker directly
        if paper_trading_enabled?
          return create_paper_tracker!(
            instrument: instrument,
            pick: pick,
            side: side,
            quantity: quantity,
            index_cfg: index_cfg,
            ltp: ltp,
            entry_metadata: entry_metadata
          )
        end

        # Live trading: Place real order
        response = Orders.config.place_market(
          side: 'buy',
          segment: pick[:segment] || index_cfg[:segment],
          security_id: pick[:security_id],
          qty: quantity,
          meta: {
            client_order_id: build_client_order_id(index_cfg: index_cfg, pick: pick),
            ltp: ltp # Pass resolved LTP (from WS or API)
          }
        )

        order_no = extract_order_no(response)
        unless order_no
          Rails.logger.warn("[EntryGuard] Order placement failed for #{index_cfg[:key]}: #{pick[:symbol]} (response: #{response.inspect})")
          return false
        end

        create_tracker!(
          instrument: instrument,
          order_no: order_no,
          pick: pick,
          side: side,
          quantity: quantity,
          index_cfg: index_cfg,
          ltp: ltp,
          entry_metadata: entry_metadata
        )

        Rails.logger.info("[EntryGuard] Successfully placed order #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]}")
        true
      rescue StandardError => e
        Rails.logger.error("EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
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

        # If this would be the second position, check pyramiding rules
        if current_count == 1
          first_position = active_positions.first

          # Reload to get latest data
          first_position.reload

          # Try to hydrate PnL from Redis cache first (has live PnL data)
          first_position.hydrate_pnl_from_cache!

          # If PnL is still nil or zero, calculate it (especially for paper positions or if Redis cache is empty)
          if (first_position.last_pnl_rupees.nil? || first_position.last_pnl_rupees.zero?) && first_position.entry_price.present? && first_position.quantity.present?
            calculate_current_pnl(first_position)
            # Reload after calculation to get updated PnL
            first_position.reload
          end

          unless pyramiding_allowed?(first_position)
            pnl_display = first_position.last_pnl_rupees ? "₹#{first_position.last_pnl_rupees.round(2)}" : 'N/A'
            Rails.logger.warn("[EntryGuard] Pyramiding not allowed for #{instrument.symbol_name}: first position PnL=#{pnl_display}, updated_at=#{first_position.updated_at}")
            return false
          end
        end

        Rails.logger.debug { "[EntryGuard] Exposure check passed for #{instrument.symbol_name}: #{current_count} < #{max_allowed}" }
        true
      end

      def pyramiding_allowed?(first_position)
        # Second position only allowed if first position is profitable
        return false unless first_position.last_pnl_rupees&.positive?

        # Additional check: ensure first position has been profitable for at least 5 minutes
        # to avoid premature pyramiding
        min_profit_duration = 5.minutes
        return false unless first_position.updated_at < min_profit_duration.ago

        Rails.logger.info("[Pyramiding] Allowing second position - first position profitable: ₹#{first_position.last_pnl_rupees.round(2)}")
        true
      rescue StandardError => e
        Rails.logger.error("Pyramiding check failed: #{e.message}")
        false
      end

      def calculate_current_pnl(tracker)
        return unless tracker.entry_price.present? && tracker.quantity.present?

        # For paper positions, use get_paper_ltp method
        if tracker.paper?
          ltp = get_paper_ltp_for_tracker(tracker)
          return unless ltp

          entry = BigDecimal(tracker.entry_price.to_s)
          exit_price = BigDecimal(ltp.to_s)
          qty = tracker.quantity.to_i
          gross_pnl = (exit_price - entry) * qty

          # Deduct broker fees (₹20 per order, ₹40 per trade if exited)
          pnl = BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: tracker.exited?)
          pnl_pct = ((exit_price - entry) / entry * 100).round(2)

          hwm = tracker.high_water_mark_pnl || BigDecimal(0)
          hwm = [hwm, pnl].max

          tracker.update!(
            last_pnl_rupees: pnl,
            last_pnl_pct: pnl_pct,
            high_water_mark_pnl: hwm,
            avg_price: exit_price
          )

          Rails.logger.debug { "[EntryGuard] Calculated PnL for paper position #{tracker.order_no}: PnL=₹#{pnl.round(2)}" }
          return
        end

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
        tick_data = Live::TickCache.fetch(segment, security_id)
        if tick_data&.dig(:ltp)
          ltp = BigDecimal(tick_data[:ltp].to_s)
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

      def get_paper_ltp_for_tracker(tracker)
        segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
        security_id = tracker.security_id
        return nil unless segment.present? && security_id.present?

        # Try WebSocket cache first
        cached = Live::TickCache.ltp(segment, security_id)
        return BigDecimal(cached.to_s) if cached

        # Try Redis PnL cache
        tick_data = Live::TickCache.fetch(segment, security_id)
        return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)

        # Try tradable's fetch method (derivative or instrument)
        tradable = tracker.tradable
        if tradable
          ltp = tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
          return BigDecimal(ltp.to_s) if ltp
        end

        # Fallback: Direct API call
        begin
          response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
          if response['status'] == 'success'
            option_data = response.dig('data', segment, security_id.to_s)
            return BigDecimal(option_data['last_price'].to_s) if option_data && option_data['last_price']
          end
        rescue StandardError => e
          Rails.logger.error("[EntryGuard] Failed to fetch LTP for #{tracker.order_no}: #{e.message}")
        end
        nil
      end

      def cooldown_active?(symbol, cooldown)
        return false if symbol.blank? || cooldown <= 0

        last = Rails.cache.read("reentry:#{symbol}")
        last.present? && (Time.current - last) < cooldown
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

        # If pick LTP is missing or zero, we need API fallback
        pick[:ltp].blank? || pick[:ltp].to_f.zero?
      end

      # Resolves LTP for entry order, prioritizing WebSocket subscription over API polling
      # Strategy: Subscribe to WebSocket feed, wait for tick, read from TickCache
      # Falls back to REST API only if WebSocket unavailable or tick doesn't arrive
      # @param instrument [Instrument]
      # @param pick [Hash] Pick data from signal
      # @param index_cfg [Hash] Index configuration
      # @return [BigDecimal, nil]
      def resolve_entry_ltp(instrument:, pick:, index_cfg:)
        segment = pick[:segment] || index_cfg[:segment]
        security_id = pick[:security_id]

        return nil unless segment.present? && security_id.present?

        hub = Live::MarketFeedHub.instance

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
              cached_ltp = Live::TickCache.ltp(segment, security_id)
              if cached_ltp.present? && cached_ltp.to_f.positive?
                Rails.logger.debug { "[EntryGuard] Got LTP from TickCache for #{segment}:#{security_id}: ₹#{cached_ltp}" }
                return BigDecimal(cached_ltp.to_s)
              end
              sleep(poll_interval_ms / 1000.0) # Convert ms to seconds
            end

            Rails.logger.debug { "[EntryGuard] No tick received from WebSocket for #{segment}:#{security_id} after #{max_wait_ms}ms, falling back to API" }
          rescue StandardError => e
            Rails.logger.warn("[EntryGuard] WebSocket subscription failed for #{segment}:#{security_id}: #{e.message}, falling back to API")
          end
        else
          Rails.logger.debug { "[EntryGuard] WebSocket not available, using API fallback for #{segment}:#{security_id}" }
        end

        # Strategy 2: REST API fallback (only if WebSocket unavailable or no tick received)
        # Try to resolve via instrument/derivative object
        if pick[:derivative_id].present?
          derivative = Derivative.find_by(id: pick[:derivative_id])
          if derivative
            api_ltp = derivative.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
            return BigDecimal(api_ltp.to_s) if api_ltp.present?
          end
        end

        # Fallback to instrument method
        api_ltp = instrument.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        return BigDecimal(api_ltp.to_s) if api_ltp.present?

        Rails.logger.warn("[EntryGuard] Failed to resolve LTP from API for #{segment}:#{security_id}")
        nil
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Error resolving entry LTP: #{e.class} - #{e.message}")
        nil
      end

      # Check if time regime allows entry
      def time_regime_allows_entry?(index_cfg:, pick:, direction:)
        return true unless time_regime_rules_enabled?

        regime_service = Live::TimeRegimeService.instance
        regime = regime_service.current_regime

        # Global override: No new trades after 14:50 (unless exceptional conditions)
        unless regime_service.allow_new_trades?
          Rails.logger.info("[EntryGuard] Entry blocked: No new trades allowed after #{Live::TimeRegimeService::NO_NEW_TRADES_AFTER}")
          return false
        end

        # Check if entries are allowed in current regime
        unless regime_service.allow_entries?(regime)
          Rails.logger.info("[EntryGuard] Entry blocked: Regime #{regime} does not allow entries")
          return false
        end

        # Check minimum ADX requirement for regime
        min_adx = regime_service.min_adx_requirement(regime)
        if min_adx > 15.0 # Only check if stricter than default
          # Get ADX from signal metadata or calculate
          # For now, skip ADX check here (should be done in signal generation)
          # This is a safety net - signal generation should already filter by ADX
        end

        # Special rules for CHOP_DECAY regime (very strict)
        if regime == Live::TimeRegimeService::CHOP_DECAY
          # Allow ONLY if exceptional conditions (ADX ≥ 22, expansion present, large impulse)
          # This should be checked in signal generation, but we log here
          Rails.logger.info('[EntryGuard] Entry in CHOP_DECAY regime - ensure exceptional conditions met')
        end

        # Special rules for CLOSE_GAMMA regime
        if regime == Live::TimeRegimeService::CLOSE_GAMMA
          # Use IST timezone explicitly
          current_time = Live::TimeRegimeService.instance.current_ist_time.strftime('%H:%M')
          if current_time >= '14:45'
            # No fresh breakouts after 14:45 IST - only continuation moves
            # This should be checked in signal generation
            Rails.logger.info('[EntryGuard] Entry after 14:45 IST - ensure continuation move only')
          end
        end

        true
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] time_regime_allows_entry? error: #{e.class} - #{e.message}")
        true # Fail-safe: allow entry if check fails
      end

      def time_regime_rules_enabled?
        AlgoConfig.fetch.dig(:time_regimes, :enabled) == true
      rescue StandardError
        false
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
              "[EntryGuard] Daily loss limit exceeded for #{index_cfg[:key]}: " \
              "₹#{result[:daily_loss].round(2)}/₹#{result[:max_daily_loss]}"
            )
            return false
          when 'global_daily_loss_limit_exceeded'
            Rails.logger.warn(
              '[EntryGuard] Global daily loss limit exceeded: ' \
              "₹#{result[:global_daily_loss].round(2)}/₹#{result[:max_global_loss]}"
            )
            return false
          when 'daily_profit_target_reached'
            Rails.logger.info(
              '[EntryGuard] Daily profit target reached: ' \
              "₹#{result[:global_daily_profit].round(2)}/₹#{result[:max_daily_profit]}"
            )
            return false
          end
          return false
        end

        true
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] daily_limits_allow_entry? error: #{e.class} - #{e.message}")
        true # Fail-safe: allow entry if check fails
      end

      def daily_limits_enabled?
        config = AlgoConfig.fetch[:risk] || {}
        daily_limits_cfg = config[:daily_limits] || {}
        daily_limits_cfg[:enable] != false
      rescue StandardError
        true # Default to enabled
      end

      private

      # Removed ensure_ws_connection! - no longer needed
      # WebSocket status is checked inline in try_enter for logging only
      # REST API fallback is always used when WS unavailable

      def find_instrument(index_cfg)
        segment_code = index_cfg[:segment]
        instrument = Instrument.find_by_sid_and_segment(
          security_id: index_cfg[:sid],
          segment_code: segment_code,
          symbol_name: index_cfg[:key]
        )

        unless instrument
          # Rails.logger.warn(
          #   "[EntryGuard] Instrument lookup failed for #{index_cfg[:key]} (segment: #{segment_code}, sid: #{index_cfg[:sid]})"
          # )
        end

        instrument
      end

      def build_client_order_id(index_cfg:, pick:)
        # DhanHQ correlation_id limit is 25 characters
        # Format: AS-{KEY}-{SID}-{TIMESTAMP}
        # Keep it under 25 chars by using shorter timestamp
        timestamp = Time.current.to_i.to_s[-6..] # Last 6 digits of timestamp
        "AS-#{index_cfg[:key][0..3]}-#{pick[:security_id]}-#{timestamp}"
      end

      def extract_order_no(response)
        return if response.blank?

        if response.respond_to?(:order_id)
          response.order_id
        elsif response.is_a?(Hash)
          response[:order_id] || response[:order_no]
        elsif response.respond_to?(:[]) # Struct-like (e.g., OpenStruct)
          response[:order_id] || response[:order_no] || response.order_id
        end
      end

      def paper_trading_enabled?
        AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
      end

      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata: nil)
        # Generate synthetic order number for paper trading
        order_no = "PAPER-#{index_cfg[:key]}-#{pick[:security_id]}-#{Time.current.to_i}"

        # Determine watchable: derivative for options, instrument for indices
        watchable = find_watchable_for_pick(pick: pick, instrument: instrument)

        # Build meta hash with entry strategy/path information
        meta_hash = {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current,
          paper_trading: true
        }

        # Add entry strategy/path metadata if provided
        if entry_metadata.is_a?(Hash)
          meta_hash[:entry_path] = entry_metadata[:entry_path] if entry_metadata[:entry_path]
          meta_hash[:entry_strategy] = entry_metadata[:strategy] if entry_metadata[:strategy]
          meta_hash[:entry_strategy_mode] = entry_metadata[:strategy_mode] if entry_metadata[:strategy_mode]
          meta_hash[:entry_timeframe] = entry_metadata[:effective_timeframe] || entry_metadata[:primary_timeframe]
          if entry_metadata[:confirmation_timeframe]
            meta_hash[:entry_confirmation_timeframe] =
              entry_metadata[:confirmation_timeframe]
          end
          meta_hash[:entry_validation_mode] = entry_metadata[:validation_mode] if entry_metadata[:validation_mode]
        end

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
          meta: meta_hash
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
        true
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist paper tracker: #{e.record.errors.full_messages.to_sentence}")
        false
      end

      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata: nil)
        # Determine watchable: derivative for options, instrument for indices
        watchable = find_watchable_for_pick(pick: pick, instrument: instrument)

        # Build meta hash with entry strategy/path information
        meta_hash = {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current
        }

        # Add entry strategy/path metadata if provided
        if entry_metadata.is_a?(Hash)
          meta_hash[:entry_path] = entry_metadata[:entry_path] if entry_metadata[:entry_path]
          meta_hash[:entry_strategy] = entry_metadata[:strategy] if entry_metadata[:strategy]
          meta_hash[:entry_strategy_mode] = entry_metadata[:strategy_mode] if entry_metadata[:strategy_mode]
          meta_hash[:entry_timeframe] = entry_metadata[:effective_timeframe] || entry_metadata[:primary_timeframe]
          if entry_metadata[:confirmation_timeframe]
            meta_hash[:entry_confirmation_timeframe] =
              entry_metadata[:confirmation_timeframe]
          end
          meta_hash[:entry_validation_mode] = entry_metadata[:validation_mode] if entry_metadata[:validation_mode]
        end

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
          meta: meta_hash
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist tracker for order #{order_no}: #{e.record.errors.full_messages.to_sentence}")
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

        # Fallback to instrument (for index positions)
        instrument
      end
    end
  end
end
