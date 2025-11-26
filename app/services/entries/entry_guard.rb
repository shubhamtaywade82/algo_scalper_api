# frozen_string_literal: true

module Entries
  class EntryGuard
    class << self
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1)
        instrument = find_instrument(index_cfg)
        unless instrument
          Rails.logger.warn("[EntryGuard] Instrument not found for #{index_cfg[:key]} (segment: #{index_cfg[:segment]}, sid: #{index_cfg[:sid]})")
          return false
        end

        # Check trading session timing (9:20 AM to 3:15 PM IST)
        session_check = TradingSession::Service.entry_allowed?
        unless session_check[:allowed]
          Rails.logger.warn("[EntryGuard] Entry blocked: #{session_check[:reason]}")
          return false
        end

        # NEW: Check daily limits before allowing entry
        daily_limits = Live::DailyLimits.new
        limit_check = daily_limits.can_trade?(index_key: index_cfg[:key])
        unless limit_check[:allowed]
          Rails.logger.warn(
            "[EntryGuard] Trading blocked for #{index_cfg[:key]}: #{limit_check[:reason]} " \
            "(daily_loss: #{limit_check[:daily_loss]&.round(2)}, " \
            "daily_trades: #{limit_check[:daily_trades]})"
          )
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

        paper_mode = paper_trading_enabled?
        force_paper = false

        quantity = Capital::Allocator.qty_for(
          index_cfg: index_cfg,
          entry_price: ltp.to_f,
          derivative_lot_size: pick[:lot_size],
          scale_multiplier: multiplier
        )
        if quantity <= 0
          if !paper_mode && auto_paper_fallback_enabled? &&
             insufficient_live_balance?(entry_price: ltp, lot_size: pick[:lot_size])
            fallback_qty = fallback_quantity(pick: pick, multiplier: multiplier)
            if fallback_qty <= 0
              Rails.logger.warn("[EntryGuard] Paper fallback calculated invalid quantity for #{index_cfg[:key]}: #{pick[:symbol]} (lot_size: #{pick[:lot_size]}, multiplier: #{multiplier})")
              return false
            end
            quantity = fallback_qty
            paper_mode = true
            force_paper = true
            Rails.logger.warn(
              "[EntryGuard] Insufficient live balance for #{index_cfg[:key]} (symbol: #{pick[:symbol]}). " \
              "Falling back to paper mode with quantity #{quantity}."
            )
          else
            Rails.logger.warn("[EntryGuard] Invalid quantity for #{index_cfg[:key]}: #{pick[:symbol]} (qty: #{quantity}, ltp: #{ltp}, lot_size: #{pick[:lot_size]})")
            return false
          end
        end

        # Validate segment is tradable (indices are not tradable)
        segment = pick[:segment] || index_cfg[:segment]
        unless segment_tradable?(segment)
          Rails.logger.error(
            "[EntryGuard] Cannot create position for non-tradable segment #{segment} " \
            "(#{index_cfg[:key]}: #{pick[:symbol]}). Indices are not tradable."
          )
          return false
        end

        tracker =
          if paper_mode
            create_paper_tracker!(
              instrument: instrument,
              pick: pick,
              side: side,
              quantity: quantity,
              index_cfg: index_cfg,
              ltp: ltp
            )
          else
            # Live trading: Place real order
            response = Orders.config.place_market(
              side: 'buy',
              segment: segment,
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

            created = create_tracker!(
              instrument: instrument,
              order_no: order_no,
              pick: pick,
              side: side,
              quantity: quantity,
              index_cfg: index_cfg,
              ltp: ltp
            )
            Rails.logger.info("[EntryGuard] Successfully placed order #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]}") if created
            created
          end

        unless tracker
          Rails.logger.warn("[EntryGuard] Failed to persist tracker for #{index_cfg[:key]}: #{pick[:symbol]}")
          return false
        end

        tag_fallback_tracker(tracker, reason: 'insufficient_live_balance') if force_paper && tracker

        post_entry_wiring(tracker: tracker, side: side, index_cfg: index_cfg)
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
          pnl = (exit_price - entry) * qty
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
          pnl_pct = entry.positive? ? ((ltp - entry) / entry * 100).round(2) : nil

          hwm = tracker.high_water_mark_pnl || BigDecimal(0)
          hwm = [hwm, pnl].max

          tracker.update!(
            last_pnl_rupees: pnl,
            last_pnl_pct: pnl_pct,
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
          # Subscribe to the strike/derivative immediately (only if not already subscribed)
          begin
            if hub.subscribed?(segment: segment, security_id: security_id)
              Rails.logger.debug { "[EntryGuard] Already subscribed to #{segment}:#{security_id}, using existing subscription" }
            else
              hub.subscribe(segment: segment, security_id: security_id)
              Rails.logger.debug { "[EntryGuard] Subscribed to #{segment}:#{security_id} for LTP resolution" }
            end

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

      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:)
        # Generate synthetic order number for paper trading
        order_no = "PAPER-#{index_cfg[:key]}-#{pick[:security_id]}-#{Time.current.to_i}"

        # Determine watchable: derivative for options, instrument for indices
        watchable = find_watchable_for_pick(pick: pick, instrument: instrument)

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
          meta: {
            index_key: index_cfg[:key],
            direction: side,
            placed_at: Time.current,
            paper_trading: true
          }
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
          hwm_pnl_pct: 0.0,
          timestamp: Time.current,
          tracker: tracker
        )

        # Add to ActiveCache immediately (ensures exit conditions work)
        # Calculate default SL/TP if needed
        sl_price = calculate_default_sl(tracker, ltp)
        tp_price = calculate_default_tp(tracker, ltp)
        add_to_active_cache(tracker: tracker, sl_price: sl_price, tp_price: tp_price)

        Rails.logger.info("[EntryGuard] Paper trading: Created position #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]} (qty: #{quantity}, entry: ₹#{ltp}, watchable: #{watchable.class.name})")
        tracker
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist paper tracker: #{e.record.errors.full_messages.to_sentence}")
        nil
      end

      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:)
        # Determine watchable: derivative for options, instrument for indices
        watchable = find_watchable_for_pick(pick: pick, instrument: instrument)

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
          meta: { index_key: index_cfg[:key], direction: side, placed_at: Time.current }
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist tracker for order #{order_no}: #{e.record.errors.full_messages.to_sentence}")
        nil
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

      def segment_tradable?(segment)
        return false if segment.blank?

        Orders::Placer::VALID_TRADABLE_SEGMENTS.include?(segment.to_s.upcase)
      end

      def post_entry_wiring(tracker:, side:, index_cfg:)
        entry_price = tracker.entry_price.to_f
        sl_price, tp_price = initial_bracket_prices(entry_price: entry_price, side: side, index_cfg: index_cfg)

        if auto_subscribe_enabled?
          subscribe_to_option_feed(tracker)
          add_to_active_cache(tracker: tracker, sl_price: sl_price, tp_price: tp_price)
        end

        place_initial_bracket(tracker: tracker, sl_price: sl_price, tp_price: tp_price)
      end

      # rubocop:disable Lint/UnusedMethodArgument
      def initial_bracket_prices(entry_price:, side:, index_cfg:)
        return [nil, nil] unless entry_price&.positive?

        risk_cfg = AlgoConfig.fetch[:risk] || {}
        sl_pct = safe_percentage(risk_cfg[:sl_pct]) || 0.30
        tp_pct = safe_percentage(risk_cfg[:tp_pct]) || 0.60

        [
          (entry_price * (1 - sl_pct)).round(2),
          (entry_price * (1 + tp_pct)).round(2)
        ]
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Failed to compute initial brackets: #{e.class} - #{e.message}")
        [nil, nil]
      end
      # rubocop:enable Lint/UnusedMethodArgument

      def safe_percentage(value)
        pct = value.to_f
        pct.positive? && pct < 1.0 ? pct : nil
      end

      def subscribe_to_option_feed(tracker)
        return unless option_segment?(tracker.segment)

        Live::MarketFeedHub.instance.subscribe_instrument(segment: tracker.segment, security_id: tracker.security_id)
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Feed subscribe failed for tracker #{tracker.id}: #{e.class} - #{e.message}")
      end

      def add_to_active_cache(tracker:, sl_price:, tp_price:)
        Positions::ActiveCache.instance.add_position(
          tracker: tracker,
          sl_price: sl_price,
          tp_price: tp_price
        )
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] ActiveCache add_position failed for tracker #{tracker.id}: #{e.class} - #{e.message}")
      end

      def place_initial_bracket(tracker:, sl_price:, tp_price:)
        Orders::BracketPlacer.place_bracket(
          tracker: tracker,
          sl_price: sl_price,
          tp_price: tp_price,
          reason: 'initial_bracket'
        )
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Initial bracket placement failed for tracker #{tracker.id}: #{e.class} - #{e.message}")
      end

      def auto_subscribe_enabled?
        feature_flags[:enable_auto_subscribe_unsubscribe] == true
      end

      def feature_flags
        AlgoConfig.fetch[:feature_flags] || {}
      rescue StandardError
        {}
      end

      def option_segment?(segment)
        seg = segment.to_s.upcase
        seg.include?('FNO') || seg.include?('COMM') || seg.include?('CUR')
      end

      def auto_paper_fallback_enabled?
        feature_flags[:auto_paper_on_insufficient_balance] == true
      rescue StandardError
        false
      end

      def insufficient_live_balance?(entry_price:, lot_size:)
        lot = lot_size.to_i
        return false unless lot.positive?

        price = entry_price.to_f
        return false unless price.positive?

        capital_available = Capital::Allocator.available_cash
        return false unless capital_available

        required = price * lot
        capital_available.to_f < required
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Failed to evaluate live balance: #{e.class} - #{e.message}")
        false
      end

      def fallback_quantity(pick:, multiplier:)
        lot = pick[:lot_size].to_i
        lot = 1 if lot <= 0
        [lot * multiplier, lot].max
      end

      def tag_fallback_tracker(tracker, reason:)
        meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
        tracker.update!(meta: meta.merge('fallback_to_paper' => true, 'fallback_reason' => reason))
      rescue StandardError => e
        Rails.logger.warn("[EntryGuard] Failed to tag fallback tracker #{tracker.id}: #{e.class} - #{e.message}")
      end

      # Calculate default stop loss price
      def calculate_default_sl(_tracker, entry_price)
        risk_cfg = AlgoConfig.fetch.dig(:risk) || {}
        sl_pct = risk_cfg[:sl_pct] || 5.0 # Default 5% stop loss

        entry = BigDecimal(entry_price.to_s)
        sl_offset = entry * (BigDecimal(sl_pct.to_s) / 100.0)

        # For long positions, SL is below entry
        entry - sl_offset
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] calculate_default_sl failed: #{e.class} - #{e.message}")
        nil
      end

      # Calculate default take profit price
      def calculate_default_tp(_tracker, entry_price)
        risk_cfg = AlgoConfig.fetch.dig(:risk) || {}
        tp_pct = risk_cfg[:tp_pct] || 10.0 # Default 10% take profit

        entry = BigDecimal(entry_price.to_s)
        tp_offset = entry * (BigDecimal(tp_pct.to_s) / 100.0)

        # For long positions, TP is above entry
        entry + tp_offset
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] calculate_default_tp failed: #{e.class} - #{e.message}")
        nil
      end
    end
  end
end
