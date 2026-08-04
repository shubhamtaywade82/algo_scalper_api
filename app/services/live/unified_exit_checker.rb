# frozen_string_literal: true

# Unified Exit Checker - KISS Principle
# Single method that checks all exit conditions in priority order
module Live
  class UnifiedExitChecker
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

        result = engine.evaluate(context)
        
        return nil if result.nil? || result.no_action? || result.skip?

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
        return @exit_config if @exit_config && @exit_config_expires_at && now < @exit_config_expires_at
        @exit_config = build_exit_config
        @exit_config_expires_at = now + EXIT_CONFIG_TTL
        @exit_config
      end

      def build_exit_config
        algo_cfg = AlgoConfig.fetch
        risk_cfg = algo_cfg[:risk] || {}
        exit_cfg = algo_cfg[:exit] || {}
        sl_value_pct = risk_cfg[:sl_pct] || exit_cfg.dig(:stop_loss, :value) || 0.12
        tp_value = exit_cfg[:take_profit] || risk_cfg[:tp_pct] || 0.50
        trailing_activation = exit_cfg.dig(:trailing, :activation_profit) || risk_cfg.dig(:trailing, :activation_pct) || 0.035
        trailing_drop = exit_cfg.dig(:trailing, :drop_threshold) || risk_cfg.dig(:trailing, :drawdown_pct) || 0.025
        {
          stop_loss: { type: exit_cfg.dig(:stop_loss, :type) || 'static', value: sl_value_pct.to_f },
          take_profit: tp_value.to_f,
          trailing: { enabled: exit_cfg.dig(:trailing, :enabled) != false, type: exit_cfg.dig(:trailing, :type) || 'adaptive', activation_profit: trailing_activation.to_f, drop_threshold: trailing_drop.to_f },
          early_exit: { enabled: exit_cfg.dig(:early_exit, :enabled) != false, profit_threshold: exit_cfg.dig(:early_exit, :profit_threshold) || 0.07 },
          premium_momentum_failure: { enabled: risk_cfg.dig(:exits, :premium_momentum_failure, :enabled) != false },
          time_based: { enabled: exit_cfg.dig(:time_based, :enabled) == true, exit_time: exit_cfg.dig(:time_based, :exit_time) || '15:20' }
        }
      end

      def trailing_armed?(tracker, snapshot, config)
        trailing_cfg = config[:trailing] || {}
        return false unless trailing_cfg[:enabled]
        activation = trailing_cfg[:activation_profit].to_f
        return false unless activation.positive?
        hwm = snapshot[:hwm_pnl].to_f
        return false unless hwm.positive?
        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return false unless entry_value.positive?
        (hwm / entry_value) >= activation
      end

      def adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers, tightening_multiplier: 1.0)
        allowed_dd = Positions::TrailingConfig.adaptive_drawdown_for_peak(peak_profit_pct, adaptive_tiers)
        return false unless allowed_dd && peak_profit_pct.positive?
        hwm = snapshot[:hwm_pnl].to_f
        pnl_value = snapshot[:pnl].to_f
        effective_allowed_dd = allowed_dd * (tightening_multiplier || 1.0).to_f
        drop_from_peak_pct = (hwm - pnl_value) / hwm * peak_profit_pct
        drop_from_peak_pct >= effective_allowed_dd
      end

      def check_smc_navigator_exit(tracker, snapshot)
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        return unless cfg[:enabled] && tracker.created_at && (Time.current - tracker.created_at) >= (cfg[:min_hold_seconds] || 120)
        ltp = snapshot[:ltp].to_f
        return unless ltp.positive? && tracker.instrument
        result = Smc::Navigator.evaluate_exit(tracker: tracker, ltp: ltp, instrument: tracker.instrument)
        return unless result.suggest_exit? && result.confidence >= (cfg[:min_confidence] || 0.65)
        { exit: true, reason: "SMC_NAVIGATOR_EXIT (#{result.reason})", path: 'smc_navigator' }
      end

      def check_structure_invalidation(tracker, snapshot)
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}
        return unless cfg.fetch(:enabled, true) && tracker.meta&.dig('structure_invalidation_price') && (Time.current - tracker.created_at) >= (cfg[:min_hold_seconds] || 90)
        underlying_ltp = resolve_underlying_ltp(tracker.meta['index_key'])
        return unless underlying_ltp
        if cfg[:underlying_move_pct] && cfg[:premium_drop_pct]
          return { exit: true, reason: "STRUCTURE_INVALIDATION (underlying move + premium drop)", path: 'structure_invalidation' } if dual_condition_met?(tracker, underlying_ltp, snapshot[:ltp].to_f, cfg)
        elsif structure_invalidated?(tracker, underlying_ltp, tracker.meta['structure_invalidation_price'])
          return { exit: true, reason: "STRUCTURE_INVALIDATION (underlying #{underlying_ltp.round(2)} broke #{tracker.meta['structure_invalidation_price']})", path: 'structure_invalidation' }
        end
        nil
      end

      def structure_invalidated?(tracker, underlying_ltp, invalidation_price)
        direction = tracker.meta&.dig('direction').to_s
        level = invalidation_price.to_f
        pct = (AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation, :buffer_pct) || 0.002).to_f
        buffer = (level * pct).abs
        direction == 'long_pe' ? underlying_ltp > level + buffer : (direction == 'long_ce' ? underlying_ltp < level - buffer : false)
      end

      private

      def resolve_stall_minutes(tracker)
        pmf_cfg = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}
        default_stall = 3

        index_key = tracker.meta&.dig('index_key')
        base = if index_key
                 pmf_cfg.dig(:index_overrides, index_key.to_sym, :stall_minutes) ||
                   pmf_cfg[:default_stall_minutes] || default_stall
               else
                 pmf_cfg[:default_stall_minutes] || default_stall
               end

        session = detect_current_session
        additive = session ? (pmf_cfg.dig(:session_overrides, session, :stall_minutes_add) || 0) : 0

        (base.to_f + additive.to_f).to_i
      rescue StandardError
        3
      end
    end
  end
end
