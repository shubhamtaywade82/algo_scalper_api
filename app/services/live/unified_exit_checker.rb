# frozen_string_literal: true

# Unified Exit Checker - KISS Principle
# Single method that checks all exit conditions in priority order
module Live
  class UnifiedExitChecker
    EXIT_CONFIG_TTL = 30 # seconds — matches AlgoConfig.fetch TTL

    class << self
      include Live::UnderlyingLtpResolver
      include Live::StructureInvalidationEvaluator
      include Live::UnderlyingContextEvaluator
      include SessionDetector

      # Returns: { exit: true/false, reason: "...", path: "..." } or nil
      def check_exit_conditions(tracker)
        snapshot = pnl_snapshot(tracker)
        return nil unless snapshot

        # Use the RuleEngine with exit rules
        engine = Risk::Rules::RuleEngine.new(
          rules: Risk::Rules::RuleFactory.exit_rules(AlgoConfig.fetch)
        )

        # Build RuleContext
        context = Risk::Rules::RuleContext.new(
          position: OpenStruct.new(
            current_ltp: snapshot[:ltp],
            pnl_pct: snapshot[:pnl_pct],
            pnl_rupees: snapshot[:pnl],
            hwm_pnl: snapshot[:hwm_pnl],
            peak_profit_pct: (tracker.entry_price.to_f > 0 ? (snapshot[:hwm_pnl].to_f / (tracker.entry_price.to_f * tracker.quantity.to_i)) : 0)
          ),
          tracker: tracker,
          tracker_snapshot: snapshot,
          risk_config: AlgoConfig.fetch
        )

        # 4. Premium Momentum Failure (if enabled)
        if premium_momentum_failure_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'PREMIUM_MOMENTUM_FAILURE',
            path: 'premium_momentum_failure',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 5. Trailing Stop (if enabled)
        if trailing_stop_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'TRAILING_STOP',
            path: 'trailing_stop',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # Map RuleResult back to the legacy hash format for compatibility
        {
          exit: true,
          reason: result.reason,
          path: result.metadata[:path] || result.rule_name,
          pnl_pct: (snapshot[:pnl_pct].to_f * 100.0).round(2)
        }
      end

      # --- START OF COMPATIBILITY HELPERS (Used by specs and Rules) ---

      def pnl_snapshot(tracker)
        Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
      rescue StandardError
        nil
      end



      def portfolio_floor_breach?
        Portfolio::DrawdownGuard.triggered?
      rescue StandardError
        false
      end

      def emergency_peak_loss_exit_triggered?(tracker)
        drawdown_cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
        return false if drawdown_cfg[:emergency_peak_loss_exit] == false

        min_peak_pct = (drawdown_cfg[:emergency_min_peak_pct] || 0.10).to_f
        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return false if entry_value <= 0

        peak_pct = tracker.high_water_mark_pnl.to_f / entry_value
        current_pct = tracker.current_pnl_pct.to_f

        peak_pct >= min_peak_pct && current_pct < -0.02
      end

      def early_exit_triggered?(tracker, snapshot)
        config = exit_config
        return false unless config[:early_exit][:enabled]
        pnl_pct = snapshot[:pnl_pct].to_f
        return false if pnl_pct >= config[:early_exit][:profit_threshold].to_f
        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument
        position_data = build_position_data(tracker, snapshot, instrument)
        Live::EarlyTrendFailure.early_trend_failure?(position_data)
      end

      def loss_limit_hit?(tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f
        if pnl_pct.negative? && config[:stop_loss][:type] == 'adaptive'
          allowed_loss = Positions::DrawdownSchedule.reverse_dynamic_sl_pct(
            pnl_pct,
            seconds_below_entry: seconds_below_entry(tracker),
            atr_ratio: calculate_atr_ratio(tracker)
          )
          return true if allowed_loss && pnl_pct <= -allowed_loss
        end
        pnl_pct <= -config[:stop_loss][:value].to_f
      end

      def percentage_pnl_exit_hit?(tracker, snapshot)
        cfg = AlgoConfig.fetch.dig(:risk, :percentage_pnl_exit) || {}
        return false unless cfg[:enabled]
        target = cfg[:target_pct].to_f
        return false unless target.positive?
        pnl_pct = snapshot[:pnl_pct].to_f
        return false unless pnl_pct >= target
        return false if trailing_armed?(tracker, snapshot, exit_config)
        true
      end

      def profit_target_hit?(tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f
        tp = config[:take_profit].to_f
        return false unless pnl_pct >= tp
        !trailing_armed?(tracker, snapshot, config)
      end

      def trailing_stop_hit?(tracker, snapshot, tightening_multiplier: 1.0)
        config = exit_config
        return false unless config[:trailing][:enabled]
        ltp = snapshot[:ltp].to_f
        return false unless ltp.positive?
        
        symbol = tracker.symbol.to_s.upcase
        if %w[NIFTY BANKNIFTY SENSEX].any? { |s| symbol.include?(s) }
          entry_value = tracker.entry_price.to_f * tracker.quantity.to_f
          return false unless entry_value.positive?
          activation = config[:trailing][:activation_profit].to_f
          peak_profit_pct = snapshot[:hwm_pnl].to_f / entry_value
          return false if activation.positive? && peak_profit_pct < activation

          index_key = tracker.meta&.dig('index_key')&.downcase
          inst_trailing = AlgoConfig.fetch.dig(:risk, :institutional_trailing, index_key&.to_sym) || {}
          adaptive_tiers = inst_trailing[:adaptive_drawdown]

          return true if adaptive_tiers.is_a?(Array) && adaptive_tiers.any? &&
                         adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers, tightening_multiplier: tightening_multiplier)

          pos_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
          prices = pos_data&.price_history || [ltp]
          analyzer = Orders::Analyzer.new(tracker: tracker, ltp: ltp, prices: prices, peak_profit_pct: peak_profit_pct)
          sl_price = analyzer.recommended_sl
          return sl_price && ltp <= sl_price
        end

        ltp = snapshot[:ltp].to_f
        return false unless ltp.positive?

        # Use advanced Gamma-Aware and MFE exits for NIFTY, BANKNIFTY, and SENSEX
        symbol = tracker.symbol.to_s.upcase
        if %w[NIFTY BANKNIFTY SENSEX].any? { |s| symbol.include?(s) }
          # Guard against division by zero - skip if entry_price or quantity is invalid
          entry_value = tracker.entry_price.to_f * tracker.quantity.to_f
          return false unless entry_value.positive?

          # Do not arm gamma/MFE trailing before activation profit is reached.
          activation = config[:trailing][:activation_profit].to_f
          peak_profit_pct = snapshot[:hwm_pnl].to_f / entry_value
          return false if activation.positive? && peak_profit_pct < activation

          # 1. Resolve price history from ActiveCache for Gamma detection
          pos_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
          prices = pos_data&.price_history || [ltp]

          # 2. Use Orders::Analyzer for combined analysis
          analyzer = Orders::Analyzer.new(
            tracker: tracker,
            ltp: ltp,
            prices: prices,
            peak_profit_pct: peak_profit_pct
          )
          sl_price = analyzer.recommended_sl

          if sl_price && ltp <= sl_price
            # Identify which engine triggered the stop for logging
            # Re-running analysis components to find the trigger (minor overhead for logging)
            highest_price = tracker.entry_price.to_f * (1.0 + peak_profit_pct)
            mfe_sl = Orders::MfeExitEngine.new(
              position: tracker,
              ltp: ltp,
              entry_price: tracker.entry_price.to_f,
              highest_price: highest_price
            ).call

            reason = (mfe_sl && sl_price == mfe_sl) ? 'MFE_RETRACE_EXIT' : 'GAMMA_AWARE_TRAILING'

            Rails.logger.info("[UnifiedExitChecker] #{reason} hit for #{tracker.order_no}: ltp=#{ltp}, sl=#{sl_price}")
            return true
          end
          return false
        end

        # Fallback to legacy trailing for other instruments
        pnl = snapshot[:pnl]
        hwm = snapshot[:hwm_pnl]
        return false if hwm.nil? || hwm.zero?
        pnl_pct = snapshot[:pnl_pct].to_f
        return false if pnl_pct <= 0

        if config[:trailing][:type] == 'adaptive'
          peak_profit_pct = (hwm / (tracker.entry_price.to_f * tracker.quantity.to_i))
          activation = config[:trailing][:activation_profit].to_f
          return false if peak_profit_pct < activation
          index_key = tracker.meta&.dig('index_key') || tracker.instrument&.symbol_name
          allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(peak_profit_pct, index_key: index_key)
          if allowed_dd
            allowed_drop_from_hwm = allowed_dd / peak_profit_pct
            current_drop = (hwm - pnl) / hwm
            return current_drop >= allowed_drop_from_hwm
          end
        end

        drop_threshold = config[:trailing][:drop_threshold].to_f
        (hwm - pnl) / hwm >= drop_threshold
      end

      def time_based_exit?(_tracker)
        config = exit_config
        return false unless config[:time_based][:enabled]
        exit_time = Time.zone.parse(config[:time_based][:exit_time])
        exit_time && Time.current >= exit_time
      end

      def premium_momentum_failure_hit?(tracker, snapshot)
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}
        return false unless cfg[:enabled]
        return false unless tracker.created_at

        current_ltp = snapshot[:ltp].to_f
        current_ltp = tracker.entry_price.to_f if current_ltp <= 0

        meta = tracker.meta || {}
        peak = meta['peak_premium'].to_f
        last_peak_at = meta['peak_premium_at'] ? Time.zone.parse(meta['peak_premium_at']) : tracker.created_at

        if current_ltp > peak
          meta['peak_premium'] = current_ltp
          meta['peak_premium_at'] = Time.current.iso8601
          tracker.update_column(:meta, meta) if tracker.respond_to?(:update_column)
          return false
        end

        # Only fires on losing positions (PnL <= 0)
        return false if snapshot[:pnl_pct].to_f.positive?

        stall_minutes = resolve_stall_minutes(tracker)
        elapsed_since_peak = (Time.current - last_peak_at) / 60.0

        elapsed_since_peak >= stall_minutes
      end

      def seconds_below_entry(tracker)
        cache_key = "position:below_entry:#{tracker.id}"
        cached = Rails.cache.read(cache_key)
        snapshot = pnl_snapshot(tracker)
        return 0 unless snapshot
        pnl_pct = snapshot[:pnl_pct]
        return 0 if pnl_pct.nil? || pnl_pct >= 0
        Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
        cached ? (Time.current - cached).to_i : 0
      rescue StandardError
        0
      end

      def calculate_atr_ratio(tracker)
        instrument = tracker.instrument || tracker.watchable&.instrument
        return 1.0 unless instrument
        series = instrument.candle_series(interval: '5')
        return 1.0 unless series&.candles&.any?
        candles = series.candles.last(20)
        return 1.0 if candles.size < 10
        current_atr = calculate_atr(candles.last(14))
        avg_atr = calculate_atr(candles)
        (current_atr / avg_atr).round(3) rescue 1.0
      end

      def calculate_atr(candles)
        return 0.0 if candles.size < 2
        true_ranges = candles.each_cons(2).map { |p, c| [(c.high - c.low), (c.high - p.close).abs, (c.low - p.close).abs].max }
        true_ranges.sum / true_ranges.size
      end

      def build_position_data(tracker, _snapshot, instrument)
        series = instrument.candle_series(interval: '5') rescue nil
        candles = series&.candles || []
        adx_value = instrument.adx(14, interval: '5') rescue nil
        adx_hash = adx_value.is_a?(Hash) ? adx_value : { value: adx_value }
        OpenStruct.new(
          trend_score: adx_hash[:value]&.to_f || 0,
          peak_trend_score: tracker.runtime_meta_fetch('peak_trend_score') || 0,
          adx: adx_hash[:value],
          atr_ratio: calculate_atr_ratio(tracker),
          underlying_price: tracker.entry_price.to_f,
          vwap: candles.any? ? candles.last(20).sum(&:close) / candles.last(20).size : tracker.entry_price.to_f,
          is_long?: %w[long_ce long_pe].include?(tracker.side)
        )
      end

      def exit_config
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if @exit_config && @exit_config_expires_at && now < @exit_config_expires_at
          return @exit_config
        end

        @exit_config = build_exit_config
        @exit_config_expires_at = now + EXIT_CONFIG_TTL
        @exit_config
      end

      def build_exit_config
        algo_cfg = AlgoConfig.fetch
        risk_cfg = algo_cfg[:risk] || {}
        exit_cfg = algo_cfg[:exit] || {}

        # Read SL from risk config (sl_pct stored as DECIMAL like 0.12 for 12%)
        sl_value = risk_cfg[:sl_pct]
        if sl_value
          sl_value_pct = sl_value.to_f  # Use DECIMAL directly (0.12)
        else
          sl_value_pct = exit_cfg.dig(:stop_loss, :value) || 0.12  # Default 12% as DECIMAL
        end

        # Read TP from config (can be in either location, stored as DECIMAL)
        tp_value = exit_cfg[:take_profit]
        unless tp_value
          if risk_cfg[:tp_pct]
            tp_value = risk_cfg[:tp_pct].to_f  # Use DECIMAL directly (0.50)
          else
            tp_value = 0.50  # Default 50% as DECIMAL
          end
        end

        # Read trailing config (now using DECIMAL format from algo.yml)
        trailing_activation = exit_cfg.dig(:trailing, :activation_profit)
        trailing_activation ||= risk_cfg.dig(:trailing, :activation_pct) || 0.035

        trailing_drop = exit_cfg.dig(:trailing, :drop_threshold)
        trailing_drop ||= risk_cfg.dig(:trailing, :drawdown_pct) || 0.025

        {
          stop_loss: {
            type: exit_cfg.dig(:stop_loss, :type) || 'static',
            value: sl_value_pct
          },
          take_profit: tp_value,
          trailing: {
            enabled: exit_cfg.dig(:trailing, :enabled) != false,
            type: exit_cfg.dig(:trailing, :type) || 'adaptive',
            activation_profit: trailing_activation,
            drop_threshold: trailing_drop
          },
          early_exit: {
            enabled: exit_cfg.dig(:early_exit, :enabled) != false,
            profit_threshold: exit_cfg.dig(:early_exit, :profit_threshold) || 0.07
          },
          premium_momentum_failure: {
            enabled: risk_cfg.dig(:exits, :premium_momentum_failure, :enabled) != false
          },
          time_based: {
            enabled: exit_cfg.dig(:time_based, :enabled) == true,
            exit_time: exit_cfg.dig(:time_based, :exit_time) || '15:20'
          }
        }
      rescue StandardError
        default_exit_config
      end

      def default_exit_config
        {
          stop_loss: { type: 'static', value: 0.12 },  # 12% stop loss (DECIMAL)
          take_profit: 0.50,  # 50% take profit (DECIMAL)
          trailing: { enabled: true, type: 'adaptive', activation_profit: 0.035, drop_threshold: 0.025 },
          early_exit: { enabled: true, profit_threshold: 0.07 },
          premium_momentum_failure: { enabled: true },
          time_based: { enabled: false, exit_time: '15:20' }
        }
      end

      private

      def premium_momentum_failure_hit?(tracker, snapshot)
        config = exit_config
        return false unless config[:premium_momentum_failure][:enabled]

        # Use PremiumMomentumFailureRule via RuleContext
        # We need a position-like object that has current_ltp
        ltp = snapshot[:ltp].to_f
        return false unless ltp.positive?

        position_data = OpenStruct.new(
          current_ltp: ltp,
          pnl_pct: snapshot[:pnl_pct].to_f
        )

        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: {} # Already handled in evaluate
        )

        rule = Risk::Rules::PremiumMomentumFailureRule.new(config: { enabled: true })
        result = rule.evaluate(context)
        result.exit?
      rescue StandardError => e
        Rails.logger.error("[UnifiedExitChecker] premium_momentum_failure_hit? error: #{e.message}")
        false
      end
    end
  end
end
