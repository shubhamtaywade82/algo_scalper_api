# frozen_string_literal: true

require_relative '../concerns/broker_fee_calculator'

module Entries
  class EntryGuard
    class << self
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil)
        Observability::StructuredLog.info(
          event: 'entry_attempted',
          payload: {
            service: 'Entries::EntryGuard',
            index_key: index_cfg[:key].to_s,
            direction: direction.to_s,
            symbol: pick[:symbol].to_s
          }
        )

        # Portfolio-level policy gate (fast fail before building context)
        entry_policy = Policies::EntryPolicy.new(index_cfg: index_cfg, direction: direction)
        unless entry_policy.permitted?
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'entry_policy',
              reasons: entry_policy.reasons
            }
          )
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
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'guard_pipeline',
              reason: reason.to_s
            }
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

        # Risk-level policy gate (portfolio exposure + drawdown check before broker call)
        risk_policy = Policies::RiskPolicy.new(
          index_key: index_cfg[:key].to_s,
          proposed_qty: quantity,
          entry_price: ltp.to_f,
          lot_size: lot_size
        )
        unless risk_policy.permitted?
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'risk_policy',
              reasons: risk_policy.reasons
            }
          )
          return false
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
        ).call

        unless place_cmd.success?
          Rails.logger.error("[EntryGuard] place_market failed for #{index_cfg[:key]}: #{pick[:symbol]} (#{place_cmd.reason})")
          Observability::StructuredLog.error(
            event: 'entry_order_failed',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              reason: place_cmd.reason.to_s
            }
          )
          return false
        end

          result = entry_guard_pipeline.run(context)
          if result != EntryGuardPipeline::PASS
            reason = result.is_a?(Hash) ? result[:blocked] : result.to_s
            guard_results = result.is_a?(Hash) ? result[:evaluated] : nil
            Observability::StructuredLog.info(
              event: 'entry_blocked',
              payload: {
                service: 'Entries::EntryGuard',
                index_key: index_cfg[:key].to_s,
                symbol: pick[:symbol].to_s,
                reason: reason,
                guard_results: guard_results
              }
            )
            if guard_results.present?
              signal&.record_entry_outcome('blocked', reason, extra_metadata: { 'guard_results' => guard_results })
            else
              signal&.record_entry_outcome('blocked', reason)
            end
            next false
          end

          # 2. Order Execution
          execution_result = OrderExecutionService.call(context)

          if execution_result.is_a?(Hash) && execution_result[:error]
            signal&.record_entry_outcome('blocked', execution_result[:error])
            next false
          end

          # Success - Tracker created
          signal&.record_entry_outcome('entered')
          validate_entry_price!(execution_result, context)

          # Record trade in DailyLimits
          begin
            Live::DailyLimits.new.record_trade(index_key: index_cfg[:key])
          rescue StandardError => e
            Rails.logger.error("[EntryGuard] Failed to record trade in DailyLimits: #{e.class} - #{e.message}")
          end

          true
        end

        Rails.logger.debug { "[EntryGuard] Exposure check passed for #{instrument.symbol_name}: #{current_count} < #{max_allowed}" }
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

          entry = BigDecimal(tracker.entry_price.to_s)
          exit_price = BigDecimal(ltp.to_s)
          qty = tracker.quantity.to_i
          gross_pnl = (exit_price - entry) * qty

          # Deduct broker fees (₹20 per order, ₹40 per trade if exited)
          pnl = BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: tracker.exited?)
          pnl_pct = ((exit_price - entry) / entry * 100).round(2)

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
      end

      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:, order_no:, entry_metadata:, bos_context:)
        PositionTracker.transaction do
          meta_hash = build_base_meta(index_cfg: index_cfg, pick: pick, direction: bos_context&.dig(:direction))
          apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

          snapshot = meta_hash.delete(:config_snapshot)
          version = (meta_hash.delete(:config_version) || {}).with_indifferent_access
          entry_at = meta_hash.delete(:entry_at)

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
            config_snapshot: snapshot,
            entry_at: entry_at
          )

          tracker
        end
      end

      def build_client_order_id(index_cfg:, pick:)
        "#{index_cfg[:key]}_#{pick[:symbol]}_#{Time.current.to_i}"
      end

      def find_instrument(index_cfg)
        Instrument.find_by_sid_and_segment(
          security_id: index_cfg[:sid],
          segment_code: index_cfg[:segment]
        )
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

      def legacy_extract_order_no(response)
        return response[:order_id] || response['order_id'] if response.is_a?(Hash)

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

      def validate_entry_price!(tracker, context)
        return unless tracker.respond_to?(:watchable)

        instrument = tracker.watchable
        return unless instrument.respond_to?(:intraday_ohlc)

        ohlc = instrument.intraday_ohlc(interval: '1', days: 1)
        return if ohlc.blank?

        series = CandleSeries.new(symbol: instrument.symbol_name, interval: '1')
        series.load_from_raw(ohlc)
        current_minute = Time.current.beginning_of_minute
        candle = series.candles.find { |c| c.timestamp == current_minute }
        return unless candle

        price = tracker.entry_price.to_f
        return if price.between?(candle.low, candle.high)

        deviation = if price > candle.high
                      ((price - candle.high) / candle.high * 100).round(2)
                    else
                      ((price - candle.low) / candle.low * 100).round(2)
                    end
        tag = deviation.positive? ? 'above' : 'below'
        Observability::StructuredLog.warn(
          event: 'entry_price_outside_candle',
          payload: {
            tracker_id: tracker.id,
            symbol: tracker.symbol,
            side: tracker.side,
            paper: tracker.paper,
            entry_price: price,
            candle_low: candle.low,
            candle_high: candle.high,
            deviation_pct: deviation,
            deviation_tag: tag
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[EntryGuard] validate_entry_price! failed: #{e.class} - #{e.message}")
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
        AlgoConfig.fetch.dig(:risk, :time_regimes, :enabled) == true
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

      def build_base_meta(index_cfg:, pick:, direction:)
        snapshot_fields = Entries::EntrySnapshotBuilder.build(index_cfg: index_cfg, pick: pick)

        {
          index_key: index_cfg[:key].to_s,
          symbol: pick[:symbol].to_s,
          direction: direction || pick[:direction],
          entry_at: Time.current.iso8601,
          config_version: AlgoConfig.version,
          config_snapshot: snapshot_fields[:config_snapshot],
          dte_at_entry: snapshot_fields[:dte_at_entry],
          vix_at_entry: snapshot_fields[:vix_at_entry],
          spread_guard_pct: snapshot_fields[:spread_guard_pct],
          atm_strike: snapshot_fields[:atm_strike],
          expiry_date: snapshot_fields[:expiry_date],
          entry_context: snapshot_fields[:entry_context]
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
