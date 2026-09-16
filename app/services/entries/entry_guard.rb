# frozen_string_literal: true

require 'digest'

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

      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil, signal: nil,
                    position_side: 'long')
        entry_attempt_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
              trace: trace,
              position_side: position_side
            }

            pipeline_res = entry_guard_pipeline.run(context)
            if pipeline_res != Entries::EntryGuardPipeline::PASS
              blocked_reason = blocked_reason_for(pipeline_res)
              Rails.logger.info("[EntryGuard][#{trace.decision_id}] Blocked #{index_cfg[:key]} (#{direction}): #{blocked_reason}")
              signal&.record_entry_outcome('blocked', blocked_reason)
              trace.mark_status(:rejected)
              return false
            end

            instrument = context[:instrument] || find_instrument(index_cfg)
            ltp = context[:ltp] || pick[:ltp] || (instrument ? resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg) : nil)
            dir_sym = direction.to_s.downcase.to_sym
            bullish_bias = %i[bullish long].include?(dir_sym)
            side = context[:side] || if position_side.to_s == 'short'
                                        # Selling inverts the option leg: bullish bias sells puts
                                        # (profit if price holds above strike), bearish sells calls.
                                        bullish_bias ? 'short_pe' : 'short_ce'
                                     else
                                        bullish_bias ? 'long_ce' : 'long_pe'
                                     end
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
        # NOTE (error-handling review 2026-09, wave 2): the pipeline's SizingGuard
        # blocks permission-less contexts ('permission_unresolved') before this
        # line, and every production caller passes an explicit permission — the
        # :scale_ready tail below only survives for pipeline-stubbed spec paths.
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
        quantity = cap_quantity_by_margin(quantity, position_side: position_side, pick: pick, index_cfg: index_cfg, lot_size: lot_size, ltp: ltp)
        quantity = (quantity / lot_size) * lot_size # ensure lot-aligned

        if quantity <= 0 || quantity < lot_size
          Rails.logger.warn(
            "[EntryGuard] Quantity blocked for #{index_cfg[:key]}: #{pick[:symbol]} (qty=#{quantity}, cap_qty=#{quantity_by_cap}, alloc_qty=#{quantity_by_existing_allocator}, lot_size=#{lot_size}, ltp=#{ltp})"
          )
          signal&.record_entry_outcome('blocked', 'quantity_below_minimum_lot')
          return false
        end

        result = OrderExecutionService.call(
          context.merge(instrument: instrument, ltp: ltp, side: side, quantity: quantity, bos_context: bos_context,
                        position_side: position_side)
        )

        if result.is_a?(Hash) && result[:error]
          Rails.logger.warn("[EntryGuard] Order execution failed for #{index_cfg[:key]}: #{pick[:symbol]} (#{result[:error]})")
          return false
        end

        tracker = result
        record_signal_to_order_latency!(tracker, entry_attempt_started_at)
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
              if cached_tick&.ltp&.to_f&.positive? && cached_tick.fresh?
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
        # Try to resolve via the traded contract instrument
        contract = pick_instrument(pick)
        if contract
          api_ltp = contract.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
          return BigDecimal(api_ltp.to_s) if api_ltp.present?
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

      # Time-regime entry gating lives in Entries::Guards::TimeRegimeGuard
      # (pipeline-owned). The legacy EntryGuard#time_regime_allows_entry?
      # copy was deleted in the error-handling review wave 4: it was dead
      # code (no callers), duplicated the guard's logic, read the config
      # from the wrong path (top-level :time_regimes instead of risk:), and
      # failed open on errors.

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

      # The pipeline always normalizes a block into a DecisionRejection, so the old
      # Hash check could never match and every block was persisted as the literal
      # 'pipeline_blocked' — which guard fired was unrecoverable afterwards.
      def blocked_reason_for(pipeline_res)
        return pipeline_res.message.presence || pipeline_res.code.to_s if pipeline_res.is_a?(DecisionRejection)
        return pipeline_res[:blocked].to_s if pipeline_res.is_a?(Hash) && pipeline_res[:blocked].present?

        'pipeline_blocked'
      end

      # Removed ensure_ws_connection! - no longer needed
      # WebSocket status is checked inline in try_enter for logging only
      # REST API fallback is always used when WS unavailable

      def find_instrument(index_cfg)
        segment_code = index_cfg[:segment]
        instrument = Instrument.resolve_index_by_sid_or_symbol(
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

      # Deterministic per (index, security, signal-or-time-window) so that retrying the
      # same entry attempt reproduces the same id instead of bypassing Orders::Placer's
      # client_order_id dedup (which was the point of a "duplicate order" guard at all).
      CLIENT_ORDER_ID_TIME_BUCKET_SECONDS = 5

      def build_client_order_id(index_cfg:, pick:, signal: nil)
        # DhanHQ correlation_id limit is 25 characters
        # Format: AS-{KEY}-{SID}-{HASH}
        seed = "#{index_cfg[:key]}-#{pick[:security_id]}-#{client_order_id_seed(signal)}"
        "AS-#{index_cfg[:key][0..3]}-#{pick[:security_id]}-#{Digest::SHA1.hexdigest(seed)[0, 6]}"
      end

      # Most try_enter callers don't pass a signal record, so fall back to a short time
      # bucket: concurrent/retried calls for the same opportunity collapse to one id,
      # while a later, genuinely new entry still gets a fresh one.
      def client_order_id_seed(signal)
        return signal.id if signal.respond_to?(:id) && signal.id.present?
        return signal.candle_timestamp.to_i if signal.respond_to?(:candle_timestamp) && signal.candle_timestamp.present?

        Time.current.to_i / CLIENT_ORDER_ID_TIME_BUCKET_SECONDS
      end

      # Records how long the entry attempt took from try_enter's first line to a placed
      # order, as a per-trade execution-quality KPI (queryable via TradeAnalytic/reports
      # once aggregated — no separate metrics table needed for a per-trade field).
      def record_signal_to_order_latency!(tracker, started_at)
        return unless tracker.respond_to?(:execution)

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        tracker.update_column(:execution, (tracker.execution || {}).merge('signal_to_order_ms' => elapsed_ms))
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] record_signal_to_order_latency! failed: #{e.class} - #{e.message}")
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

      # Selling's real capital-at-risk is margin, not premium — cap the premium-sized
      # quantity down to what the margin budget actually affords. Buying is untouched.
      def cap_quantity_by_margin(quantity, position_side:, pick:, index_cfg:, lot_size:, ltp:)
        return quantity unless position_side.to_s == 'short'
        return quantity if quantity <= 0

        margin_per_lot = Adapters::Margin::DhanMarginAdapter.new.margin_for(
          segment: pick[:segment] || index_cfg[:segment],
          security_id: pick[:security_id],
          quantity: lot_size,
          price: ltp
        )
        return quantity if margin_per_lot.blank? || !margin_per_lot.positive?

        lots_by_margin = (Entries::Guards::MarginLimitGuard.max_margin_budget / margin_per_lot).floor
        [quantity, lots_by_margin * lot_size].min
      rescue StandardError => e
        Rails.logger.warn("[EntryGuard] cap_quantity_by_margin failed: #{e.class} - #{e.message}")
        quantity
      end

      def find_watchable_for_pick(pick:, instrument:)
        # Post-consolidation: the traded option/contract is an Instrument row.
        # Prefer FNO segment on the (vanishingly rare) cross-segment id clash.
        Instrument.fno.find_by(security_id: pick[:security_id].to_s) ||
          Instrument.find_by(security_id: pick[:security_id].to_s) ||
          instrument
      rescue StandardError
        instrument
      end

      # Resolves the traded contract for an entry pick (shared semantics:
      # instrument_id > legacy derivative_id > security_id).
      def pick_instrument(pick)
        Instruments::LegacyResolver.resolve_pick(pick)
      end

      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata: nil, bos_context: nil)
        # Build meta hash with entry strategy/path information
        meta_hash = {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current,
          paper_trading: true
        }
        iv_at_entry = entry_iv_from_pick(pick)

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
          position_side: side.to_s.start_with?('short') ? 'short' : 'long',
          premium_received: side.to_s.start_with?('short') ? (ltp.to_f * quantity.to_i) : 0,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: :active,
          paper: false,
          index_key: index_cfg[:key],
          entry_strategy: meta_hash[:entry_strategy],
          iv_at_entry: iv_at_entry,
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
        iv_at_entry = entry_iv_from_pick(pick)

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
          position_side: side.to_s.start_with?('short') ? 'short' : 'long',
          premium_received: side.to_s.start_with?('short') ? (ltp.to_f * quantity.to_i) : 0,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: :active,
          paper: true,
          index_key: index_cfg[:key],
          iv_at_entry: iv_at_entry,
          meta: meta_hash
        )
      end

      # Entry-time implied volatility of the traded strike, stamped on the tracker
      # so the scalp IV-collapse exit (Scalp::ChainTrailingContext#iv_collapse_signal)
      # and Risk::Rules::IvCollapseRule have a baseline to compare the live chain's
      # implied_volatility against — both no-op on a nil/zero baseline, so a missing
      # value just leaves those signals dormant (previously NOTHING wrote the
      # column, making the IV-collapse exit dead code for new positions; only the
      # 2026-06-25 meta backfill ever populated it).
      #
      # Option-chain-derived picks carry the strike's IV (Options::ChainAnalyzer
      # #pick_strikes / #pick_strikes_with_qualification slice :iv; Guards::
      # IvVolGateGuard reads the same keys). Pick paths without chain data
      # (SignalScheduler#build_pick_from_signal, broker position sync) get nil.
      def entry_iv_from_pick(pick)
        raw = pick[:iv] || pick['iv'] || pick[:implied_volatility] || pick['implied_volatility']
        value = raw.to_f
        value.positive? ? value : nil
      end

      def apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price:, quantity:)
        return unless bos_context

        contract = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_contract].to_s : ''

        # Strict inputs (error-handling review 2026-09, wave 2): these values
        # pin the position's stop/target metadata for its whole life. Garbage
        # used to coerce to 0 and produce NaN stops or a fabricated ₹0 risk.
        entry_price_f = positive_entry_price!(entry_price)
        qty = Orders::Quantity.resolve!(quantity, context: 'EntryGuard BOS metadata')

        if contract == SUPERTREND_CONTRACT
          # Supertrend direct entries do not have BOS structure risk; derive premium risk from configured SL %.
          sl_decimal = supertrend_sl_decimal
          premium_r = entry_price_f * sl_decimal
          entry_risk_rupees = premium_r * qty
          origin_price = entry_price_f
          entry_underlying_price = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_underlying_price] : nil
        else
          # Non-supertrend entries carry their structural stop in the BOS origin
          # swing. A missing/zero swing price used to be written into tracker meta
          # as structure_invalidation_price = 0.0, silently disabling
          # structure-invalidation exits for the life of the trade.
          origin_price = positive_origin_swing_price!(bos_context)
          entry_underlying_price = bos_context[:entry_underlying_price]
          reference_price = entry_underlying_price || entry_price_f
          entry_risk_rupees = (reference_price.to_f - origin_price).abs * qty
          premium_r = entry_risk_rupees / qty.to_f
        end
        premium_stop = entry_price_f - premium_r
        premium_target = entry_price_f + premium_r

        meta_hash[:structure_invalidation_price] = origin_price
        meta_hash[:entry_premium] = entry_price_f
        meta_hash[:entry_risk_rupees] = entry_risk_rupees
        meta_hash[:premium_stop_price] = premium_stop
        meta_hash[:initial_sl_pct] = (premium_r / entry_price_f * 100.0).round(2)
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

      # Supertrend direct entries derive premium risk from the configured SL %.
      #
      # Error-handling review 2026-09 (wave 2): a missing/corrupt risk.sl_pct
      # used to silently become 0.12 — a WIDER stop than the shipped 0.10, with
      # no signal. The value is now mandatory.
      #
      # Test-env carve-out (same convention as AlgoConfig.run_mode): partial
      # AlgoConfig.fetch stubs keep the legacy 0.12 in test; development and
      # production refuse to guess.
      #
      # @return [Float]
      # @raise [Errors::ConfigurationError] when risk.sl_pct is missing, non-positive or non-finite
      def supertrend_sl_decimal
        raw = AlgoConfig.fetch.dig(:risk, :sl_pct)
        value = raw.to_f

        unless raw.present? && value.finite? && value.positive?
          return 0.12 if Rails.env.test?

          raise Errors::ConfigurationError,
                "risk.sl_pct must be a positive number — got #{raw.inspect}; refusing to assume a stop-loss percentage"
        end

        value
      end

      # @raise [Errors::InvalidPrice] when entry_price is not a positive finite number
      def positive_entry_price!(entry_price)
        price = entry_price.to_f
        unless entry_price.present? && price.finite? && price.positive?
          raise Errors::InvalidPrice, "entry_price must be a positive number — got #{entry_price.inspect}"
        end

        price
      end

      # @raise [Errors::InvalidMarketData] when the BOS origin swing price is
      #   missing or not a positive finite number
      def positive_origin_swing_price!(bos_context)
        raw = bos_context.dig(:origin_swing, :price)
        price = raw.to_f
        unless raw.present? && price.finite? && price.positive?
          raise Errors::InvalidMarketData,
                "bos_context[:origin_swing][:price] must be a positive number — got #{raw.inspect}; " \
                'refusing to pin a fabricated structure_invalidation_price'
        end

        price
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

      # These are collaborators' API, not internal-only helpers: OrderExecutionService and
      # BosStructureGuard call them with an explicit receiver. `private` above blocks that
      # (NoMethodError) for anything declared after it, so re-open them here.
      public :build_client_order_id, :extract_order_no, :create_tracker!, :create_paper_tracker!, :timeframe_to_interval
    end
  end
end
