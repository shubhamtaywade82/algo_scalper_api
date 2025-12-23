# frozen_string_literal: true

module Risk
  module Rules
    # Post-Profit Zone Management Rule
    # Implements state machine for managing positions after ₹2,000 profit target
    #
    # State Machine:
    # - ENTRY: ₹0 → ₹2,000 (normal trade management)
    # - SECURED_PROFIT_ZONE: ₹2,000 → ₹4,000 (capital protection mode)
    # - RUNNER_ZONE: ₹4,000+ (trailing stop with exponential drawdown)
    #
    # Core Principle: ₹2,000 TP is a minimum extraction, not a cap.
    # After ₹2k, trade continues ONLY if underlying trend + option momentum are favorable.
    #
    # @example
    #   rule = PostProfitZoneRule.new(config: {
    #     secured_profit_threshold_rupees: 2000,
    #     runner_zone_threshold_rupees: 4000,
    #     secured_sl_rupees: 800,
    #     underlying_adx_min: 18,
    #     option_pullback_max_pct: 35.0
    #   })
    class PostProfitZoneRule < BaseRule
      PRIORITY = 25 # Higher priority than TakeProfitRule (30) but after StopLossRule (20)

      # Profit zone states
      ENTRY = :entry
      SECURED_PROFIT_ZONE = :secured_profit_zone
      RUNNER_ZONE = :runner_zone

      def evaluate(context)
        return skip_result unless context.active?

        pnl_rupees = context.pnl_rupees
        return skip_result unless pnl_rupees&.positive?

        secured_threshold = config_bigdecimal(:secured_profit_threshold_rupees, BigDecimal('2000'))
        runner_threshold = config_bigdecimal(:runner_zone_threshold_rupees, BigDecimal('4000'))

        # Determine current zone
        zone = determine_zone(pnl_rupees, secured_threshold, runner_threshold)

        # Entry zone: no special handling (normal trade management)
        return no_action_result if zone == ENTRY

        # Secured Profit Zone: Check if we should exit due to trend/momentum failure
        if zone == SECURED_PROFIT_ZONE
          return evaluate_secured_profit_zone(context, pnl_rupees, secured_threshold)
        end

        # Runner Zone: Trailing stop logic (handled by TrailingStopRule, but we can add additional checks)
        if zone == RUNNER_ZONE
          return evaluate_runner_zone(context, pnl_rupees, runner_threshold)
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PostProfitZoneRule] evaluate error: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        skip_result
      end

      private

      def determine_zone(pnl_rupees, secured_threshold, runner_threshold)
        if pnl_rupees.to_f >= runner_threshold.to_f
          RUNNER_ZONE
        elsif pnl_rupees.to_f >= secured_threshold.to_f
          SECURED_PROFIT_ZONE
        else
          ENTRY
        end
      end

      def evaluate_secured_profit_zone(context, pnl_rupees, secured_threshold)
        # Check if underlying trend is still favorable
        underlying_favorable = underlying_trend_favorable?(context)

        # Check if option momentum is still intact
        option_momentum_intact = option_momentum_intact?(context)

        # Exit immediately if trend weakens OR option momentum stalls
        unless underlying_favorable && option_momentum_intact
          reason_parts = []
          reason_parts << 'underlying_trend_weak' unless underlying_favorable
          reason_parts << 'option_momentum_stalled' unless option_momentum_intact

          return exit_result(
            reason: "POST_TP_EXIT (#{reason_parts.join(', ')}) - Profit: ₹#{pnl_rupees.round(2)}",
            metadata: {
              zone: SECURED_PROFIT_ZONE,
              pnl_rupees: pnl_rupees.to_f,
              underlying_favorable: underlying_favorable,
              option_momentum_intact: option_momentum_intact,
              secured_threshold: secured_threshold.to_f
            }
          )
        end

        # Trend and momentum are favorable - continue holding
        no_action_result
      end

      def evaluate_runner_zone(context, pnl_rupees, runner_threshold)
        # Runner zone uses trailing stops (handled by TrailingStopRule)
        # But we can add additional momentum checks here if needed
        # For now, let trailing stop logic handle exits

        # Optional: Add additional momentum check even in runner zone
        if momentum_check_enabled?
          underlying_favorable = underlying_trend_favorable?(context)
          option_momentum_intact = option_momentum_intact?(context)

          unless underlying_favorable && option_momentum_intact
            reason_parts = []
            reason_parts << 'underlying_trend_weak' unless underlying_favorable
            reason_parts << 'option_momentum_stalled' unless option_momentum_intact

            return exit_result(
              reason: "RUNNER_ZONE_EXIT (#{reason_parts.join(', ')}) - Profit: ₹#{pnl_rupees.round(2)}",
              metadata: {
                zone: RUNNER_ZONE,
                pnl_rupees: pnl_rupees.to_f,
                underlying_favorable: underlying_favorable,
                option_momentum_intact: option_momentum_intact,
                runner_threshold: runner_threshold.to_f
              }
            )
          end
        end

        no_action_result
      end

      # Check if underlying trend is still favorable for options buying
      # Criteria:
      # 1. 1m Supertrend still in direction
      # 2. ADX ≥ 18 and not falling
      # 3. Candle bodies > wicks (no exhaustion)
      # 4. No HTF resistance within 30-40 pts
      def underlying_trend_favorable?(context)
        tracker = context.tracker
        return false unless tracker

        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument

        # Get underlying state from UnderlyingMonitor
        position_data = build_position_data_for_monitor(context)
        underlying_state = Live::UnderlyingMonitor.evaluate(position_data)

        # Check ADX
        adx_min = config_value(:underlying_adx_min, 18.0).to_f
        if underlying_state.trend_score
          trend_score = underlying_state.trend_score.to_f
          return false if trend_score < adx_min
        end

        # Check Supertrend direction (via trend_score breakdown or direct check)
        # If trend_score is positive and above threshold, trend is favorable
        if underlying_state.trend_score && underlying_state.trend_score.to_f < adx_min
          return false
        end

        # Check structure break
        if underlying_state.bos_state == :broken
          tracker = context.tracker
          position_direction = Positions::MetadataResolver.direction(tracker)
          if position_direction == :bullish && underlying_state.bos_direction == :bearish
            return false
          end
          if position_direction == :bearish && underlying_state.bos_direction == :bullish
            return false
          end
        end

        # Check ATR collapse (falling volatility)
        if underlying_state.atr_trend == :falling
          atr_ratio_threshold = config_value(:underlying_atr_collapse_threshold, 0.65).to_f
          if underlying_state.atr_ratio && underlying_state.atr_ratio.to_f < atr_ratio_threshold
            return false
          end
        end

        # Check candle exhaustion (bodies > wicks)
        # This is checked via trend_score - if trend_score is dropping, it indicates exhaustion
        # For now, we rely on trend_score and ADX checks above

        true
      rescue StandardError => e
        Rails.logger.error("[PostProfitZoneRule] underlying_trend_favorable? error: #{e.class} - #{e.message}")
        false # Fail-safe: assume unfavorable if check fails
      end

      # Check if option momentum is still intact
      # Criteria:
      # 1. Premium is NOT stalling
      # 2. LTP continues to make HH (higher highs)
      # 3. Pullbacks < 30-35% of last impulse
      # 4. Bid-ask spread stable
      def option_momentum_intact?(context)
        tracker = context.tracker
        return false unless tracker && context.current_ltp

        # Get recent LTP history from Redis cache
        ltp_history = get_ltp_history(tracker)
        return false if ltp_history.size < 3 # Need at least 3 data points

        current_ltp = context.current_ltp.to_f
        entry_price = context.entry_price&.to_f
        return false unless entry_price&.positive?

        # Check 1: Premium stalling (LTP not making new highs)
        pullback_max_pct = config_value(:option_pullback_max_pct, 35.0).to_f
        recent_highs = ltp_history.last(5).map { |h| h[:ltp].to_f }
        recent_high = recent_highs.max

        # If current LTP is significantly below recent high, momentum may be stalling
        if recent_high > current_ltp
          pullback_pct = ((recent_high - current_ltp) / recent_high) * 100.0
          return false if pullback_pct > pullback_max_pct
        end

        # Check 2: LTP making higher highs (over longer period)
        # Compare current LTP to entry and recent history
        if ltp_history.size >= 5
          older_highs = ltp_history.first(5).map { |h| h[:ltp].to_f }
          older_high = older_highs.max

          # If current is not making new highs relative to older period, momentum weakening
          if current_ltp < older_high * 1.05 # Allow 5% tolerance
            return false
          end
        end

        # Check 3: Pullback from peak (if we have HWM data)
        hwm = context.high_water_mark
        if hwm && hwm.to_f.positive?
          peak_ltp = hwm.to_f / context.quantity.to_f + entry_price.to_f
          if peak_ltp > current_ltp
            pullback_from_peak = ((peak_ltp - current_ltp) / peak_ltp) * 100.0
            return false if pullback_from_peak > pullback_max_pct
          end
        end

        # Check 4: Bid-ask spread stability (if available)
        # This would require tick data with bid/ask - for now, skip if not available

        true
      rescue StandardError => e
        Rails.logger.error("[PostProfitZoneRule] option_momentum_intact? error: #{e.class} - #{e.message}")
        false # Fail-safe: assume momentum stalled if check fails
      end

      def build_position_data_for_monitor(context)
        tracker = context.tracker
        instrument = tracker.instrument || tracker.watchable&.instrument

        # Build position data hash compatible with UnderlyingMonitor
        OpenStruct.new(
          tracker_id: tracker.id,
          underlying_segment: instrument&.exchange_segment || tracker.segment,
          underlying_security_id: instrument&.security_id || tracker.meta&.dig('underlying_security_id'),
          underlying_symbol: tracker.meta&.dig('index_key') || instrument&.symbol_name,
          underlying_ltp: nil, # Will be fetched by monitor
          position_direction: Positions::MetadataResolver.direction(tracker)
        )
      end

      def get_ltp_history(tracker, lookback_candles = 10)
        # Get LTP history from Redis cache
        cache_key = "position:ltp_history:#{tracker.id}"
        cached = Rails.cache.read(cache_key)

        # If no cache, build from recent Redis PnL cache entries
        unless cached
          # Try to get recent LTP from Redis PnL cache
          redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
          if redis_pnl && redis_pnl[:ltp]
            cached = [{ ltp: redis_pnl[:ltp], timestamp: redis_pnl[:timestamp] || Time.current.to_i }]
          else
            cached = []
          end
        end

        # Update cache with current LTP
        current_ltp = tracker.last_pnl_rupees ? nil : tracker.tradable&.ltp
        if current_ltp
          cached = (cached || []).last(lookback_candles - 1)
          cached << { ltp: current_ltp, timestamp: Time.current.to_i }
          Rails.cache.write(cache_key, cached, expires_in: 1.hour)
        end

        cached || []
      rescue StandardError => e
        Rails.logger.error("[PostProfitZoneRule] get_ltp_history error: #{e.class} - #{e.message}")
        []
      end

      def momentum_check_enabled?
        config_value(:runner_zone_momentum_check, false)
      end

      def config_value(key, default = nil)
        @config[key.to_sym] || @config[key.to_s] || default
      end

      def config_bigdecimal(key, default = BigDecimal('0'))
        value = config_value(key, default)
        BigDecimal(value.to_s)
      rescue StandardError
        default
      end
    end
  end
end
