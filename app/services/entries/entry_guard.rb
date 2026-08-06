# frozen_string_literal: true

module Entries
  class EntryGuard
    ENTRY_CONTRACT = 'bos_machine_v1'
    SUPERTREND_CONTRACT = 'supertrend_machine_v1'
    BOS_SWING_LOOKBACK = 5
    BOS_MAX_AGE_CANDLES = 8
    BOS_MAX_ENTRY_DELAY_CANDLES = 3
    BOS_MAX_ENTRY_DISTANCE_R = 0.5

    class << self
      def entry_guard_pipeline
        @entry_guard_pipeline ||= EntryGuardPipeline.new
      end

      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil, signal: nil)
        Entries::AdvisoryLock.with_index_lock(index_cfg[:key]) do
          EventStore::DecisionTrace.with_trace(index_key: index_cfg[:key], direction: direction, metadata: entry_metadata || {}) do |trace|
            Rails.logger.info("[EntryGuard][#{trace.decision_id}] Attempting entry for #{index_cfg[:key]} (#{direction})")

            context = {
              index_cfg: index_cfg,
              pick: pick,
              direction: direction,
              scale_multiplier: scale_multiplier,
              entry_metadata: entry_metadata,
              permission: permission,
              signal: signal,
              trace: trace
            }

            pipeline_res = entry_guard_pipeline.run(context)
            if pipeline_res != Entries::EntryGuardPipeline::PASS
              blocked_reason = pipeline_res.is_a?(Hash) ? pipeline_res[:blocked] : 'pipeline_blocked'
              signal&.record_entry_outcome('blocked', blocked_reason)
              trace.mark_status(:rejected)
              return false
            end

            instrument = context[:instrument] || find_instrument(index_cfg)
            ltp = context[:ltp] || pick[:ltp] || (instrument ? resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg) : nil)
            dir_sym = direction.to_s.downcase.to_sym
            side = context[:side] || (%i[bullish long].include?(dir_sym) ? 'long_ce' : 'long_pe')
            is_supertrend = entry_metadata&.dig(:entry_contract).to_s == SUPERTREND_CONTRACT
            multiplier = [scale_multiplier.to_i, 1].max

            bos_context = context[:bos_context] || (if is_supertrend
                                                      {
                                                        confirmed_at: Time.current,
                                                        confirmed_index: -1,
                                                        direction: direction,
                                                        bos_id: entry_metadata&.dig(:bos_id),
                                                        timeframe: entry_metadata&.dig(:bos_timeframe),
                                                        origin_swing: { price: ltp.to_f },
                                                        broken_swing: { price: ltp.to_f },
                                                        entry_underlying_price: entry_metadata&.dig(:entry_underlying_price)
                                                      }
                                                    else
                                                      Entries::Guards::BosStructureGuard.enforce_structure_gate(
                                                        index_cfg: index_cfg,
                                                        instrument: instrument,
                                                        direction: direction,
                                                        entry_price: ltp.to_f,
                                                        entry_metadata: entry_metadata
                                                      )
                                                    end) || { confirmed_at: Time.current, confirmed_index: -1, direction: direction, origin_swing: { price: ltp.to_f }, broken_swing: { price: ltp.to_f } }

        # ===== Unified instrument profile + capital cap sizing (hard rules) =====
        symbol = index_cfg[:key].to_s.upcase
        permission_sym = (permission || entry_metadata&.dig(:permission) || :scale_ready).to_s.downcase.to_sym
        profile = Trading::InstrumentExecutionProfile.for(symbol)

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
          signal&.record_entry_outcome('blocked', 'quantity_below_minimum_lot')
          return false
        end

        result = OrderExecutionService.call(
          context.merge(instrument: instrument, ltp: ltp, side: side, quantity: quantity, bos_context: bos_context)
        )

        if result.is_a?(Hash) && result[:error]
          Rails.logger.warn("[EntryGuard] Order execution failed for #{index_cfg[:key]}: #{pick[:symbol]} (#{result[:error]})")
          return false
        end

        tracker = result
        signal&.record_entry_outcome('entered')
        trace.mark_status(:executed)

        order_identifier = tracker.try(:order_no) || tracker.try(:id) || 'ORD'
        Rails.logger.info("[EntryGuard][#{trace.decision_id}] Successfully placed order #{order_identifier} for #{index_cfg[:key]}: #{pick[:symbol]}")
        true
          end
        end
      rescue StandardError => e
        signal&.record_entry_outcome('blocked', "exception: #{e.class}")
        bt = e.backtrace&.first(12)&.join("\n")
        msg = "EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}"
        msg = "#{msg}\n#{bt}" if bt.present?
        Rails.logger.error(msg)
        false
      end

      def cooldown_active?(symbol, cooldown)
        return false if symbol.blank? || cooldown <= 0

        last = Rails.cache.read("reentry:#{symbol}")
        last.present? && (Time.current - last) < cooldown
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
              cached_tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
              if cached_tick&.ltp&.to_f&.positive?
                Rails.logger.debug { "[EntryGuard] Got LTP from TickCache for #{segment}:#{security_id}: ₹#{cached_tick.ltp}" }
                return cached_tick.ltp
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
      # EXCEPT for institutional rule of max 3 trades per day for index options.
      def daily_limits_allow_entry?(index_cfg:)
        return true unless daily_limits_enabled?

        daily_limits = Live::DailyLimits.new
        result = daily_limits.can_trade?(index_key: index_cfg[:key])

        # Institutional rule: max 3 trades per day for NIFTY/SENSEX/BANKNIFTY
        symbol = index_cfg[:key].to_s.upcase
        if %w[NIFTY SENSEX BANKNIFTY].include?(symbol)
          trades_today = daily_limits.get_daily_trades(symbol)
          if trades_today >= 3
            Rails.logger.warn("[EntryGuard] Institutional trade limit reached for #{symbol}: #{trades_today} trades today")
            return false
          end
        end

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
        # Format: AS-{KEY}-{SID}-{HEX}
        "AS-#{index_cfg[:key][0..3]}-#{pick[:security_id]}-#{SecureRandom.hex(3)}"
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

      def find_watchable_for_pick(pick:, instrument:)
        Derivative.find_by(security_id: pick[:security_id].to_s, segment: (pick[:segment] || 'NSE_FNO').to_s) || instrument
      rescue StandardError
        instrument
      end

      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata: nil, bos_context: nil)
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

        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        inst_record = if instrument.is_a?(ActiveRecord::Base) && instrument.persisted?
                        instrument
                      else
                        Instrument.find_by(symbol_name: index_cfg[:key]) || Instrument.first || Instrument.create!(symbol_name: (index_cfg[:key] || 'NIFTY').to_s, exchange: 'NSE', segment: 'index', security_id: '13')
                      end
        watchable = find_watchable_for_pick(pick: pick, instrument: inst_record) || inst_record

        PositionTracker.create!(
          order_no: order_no,
          instrument: inst_record,
          watchable: watchable,
          symbol: pick[:symbol],
          security_id: pick[:security_id],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: :active,
          paper: false,
          meta: meta_hash
        )
      end

      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:, order_no:, entry_metadata: nil, bos_context: nil)
        meta_hash = {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current,
          paper_trading: true
        }

        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        inst_record = if instrument.is_a?(ActiveRecord::Base) && instrument.persisted?
                        instrument
                      else
                        Instrument.find_by(symbol_name: index_cfg[:key]) || Instrument.first || Instrument.create!(symbol_name: (index_cfg[:key] || 'NIFTY').to_s, exchange: 'NSE', segment: 'index', security_id: '13')
                      end
        watchable = find_watchable_for_pick(pick: pick, instrument: inst_record) || inst_record

        PositionTracker.create!(
          order_no: order_no,
          instrument: inst_record,
          watchable: watchable,
          symbol: pick[:symbol],
          security_id: pick[:security_id],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: :active,
          paper: true,
          meta: meta_hash
        )
      end

      def apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price:, quantity:)
        return unless bos_context

        contract = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_contract].to_s : ''
        if contract == SUPERTREND_CONTRACT
          # Supertrend direct entries do not have BOS structure risk; derive premium risk from configured SL %.
          sl_decimal = supertrend_sl_decimal
          premium_r = entry_price.to_f * sl_decimal
          entry_risk_rupees = premium_r * quantity.to_i
          origin_price = entry_price.to_f
          entry_underlying_price = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_underlying_price] : nil
        else
          origin_price = bos_context[:origin_swing][:price].to_f
          entry_underlying_price = bos_context[:entry_underlying_price]
          reference_price = entry_underlying_price || entry_price
          entry_risk_rupees = (reference_price.to_f - origin_price).abs * quantity.to_i
          premium_r = entry_risk_rupees / quantity.to_f
        end
        premium_stop = entry_price.to_f - premium_r
        premium_target = entry_price.to_f + premium_r

        meta_hash[:structure_invalidation_price] = origin_price
        meta_hash[:entry_premium] = entry_price.to_f
        meta_hash[:entry_risk_rupees] = entry_risk_rupees
        meta_hash[:premium_stop_price] = premium_stop
        meta_hash[:initial_sl_pct] = (premium_r / entry_price.to_f * 100.0).round(2)
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

      def supertrend_sl_decimal
        value = AlgoConfig.fetch.dig(:risk, :sl_pct).to_f
        return 0.12 if value <= 0

        value
      rescue StandardError
        0.12
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

      def banknifty_monthly_expiry(instrument, today)
        expiry_list = instrument&.expiry_list&.compact
        if expiry_list.present?
          parsed = expiry_list.filter_map do |raw|
            case raw
            when Date then raw
            when String then begin
                               Date.parse(raw)
            rescue StandardError
                               nil
            end
            when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
            end
          end.sort

          monthly_expiries = parsed
                             .group_by { |d| [d.year, d.month] }
                             .map { |_, dates| dates.max }
                             .sort

          nearest = monthly_expiries.find { |d| d >= today }
          return nearest if nearest
        end

        # Fallback: last Thursday of month
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
    end
  end
end
