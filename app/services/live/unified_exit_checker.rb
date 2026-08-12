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

        pnl_pct_display = (snapshot[:pnl_pct].to_f * 100.0).round(2)

        # 1. Emergency portfolio/drawdown exits — global kill-switches, apply to every position
        return { exit: true, reason: 'PORTFOLIO_FLOOR_BREACH', path: 'profit_lock', pnl_pct: pnl_pct_display } if portfolio_floor_breach?

        # Everything below assumes a long's P&L shape (rising premium is good) and isn't
        # safe to run against a short. Selling has its own exit rules — see
        # RiskManagerService::ExitEnforcement#enforce_selling_exits_for.
        return nil if tracker.respond_to?(:short_position?) && tracker.short_position?

        return { exit: true, reason: 'EMERGENCY_PEAK_LOSS', path: 'emergency_peak_loss', pnl_pct: pnl_pct_display } if emergency_peak_loss_exit_triggered?(tracker)

        # 2. Structure invalidation / SMC Navigator
        si_res = check_structure_invalidation(tracker, snapshot)
        return { exit: true, reason: si_res[:reason], path: 'structure_invalidation', pnl_pct: pnl_pct_display } if si_res&.dig(:exit)
        return { exit: true, reason: 'SMC_NAVIGATOR_EXIT', path: 'smc_navigator', pnl_pct: pnl_pct_display } if smc_navigator_exit_hit?(tracker, snapshot)

        # 3. Hard SL / Percentage PnL / Take Profit
        return { exit: true, reason: 'STOP_LOSS', path: 'stop_loss', pnl_pct: pnl_pct_display } if loss_limit_hit?(tracker, snapshot)
        return { exit: true, reason: 'PERCENTAGE_PNL_EXIT', path: 'percentage_pnl_exit', pnl_pct: pnl_pct_display } if percentage_pnl_exit_hit?(tracker, snapshot)
        return { exit: true, reason: 'TAKE_PROFIT', path: 'take_profit', pnl_pct: pnl_pct_display } if profit_target_hit?(tracker, snapshot)

        # 4. Trailing / Momentum / Early / Time
        return { exit: true, reason: 'EARLY_TREND_FAILURE', path: 'early_exit', pnl_pct: pnl_pct_display } if early_exit_triggered?(tracker, snapshot)
        return { exit: true, reason: 'PREMIUM_MOMENTUM_FAILURE', path: 'premium_momentum_failure', pnl_pct: pnl_pct_display } if premium_momentum_failure_hit?(tracker, snapshot)

        trailing_res = evaluate_trailing_stop(tracker, snapshot)
        if trailing_res&.dig(:exit)
          return { exit: true, reason: trailing_res[:reason], path: trailing_res[:path], pnl_pct: pnl_pct_display }
        end

        return { exit: true, reason: 'TIME_BASED', path: 'time_based_exit', pnl_pct: pnl_pct_display } if time_based_exit?(tracker)

        nil
      end

      # --- START OF COMPATIBILITY HELPERS ---

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

      def check_structure_invalidation(tracker, snapshot)
        si_cfg = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}
        return nil if si_cfg[:enabled] == false

        index_key = tracker.meta&.dig('index_key') || tracker.index_key
        underlying_ltp = resolve_underlying_ltp(index_key)

        if si_cfg[:underlying_move_pct].present? && si_cfg[:premium_drop_pct].present?
          if underlying_ltp && dual_condition_met?(tracker, underlying_ltp, snapshot[:ltp], si_cfg)
            return { exit: true, reason: 'STRUCTURE_INVALIDATION (Dual Condition Met)', path: 'structure_invalidation' }
          end
        else
          invalidation_price = tracker.meta&.dig('structure_invalidation_price')&.to_f
          if invalidation_price&.positive? && underlying_ltp && structure_invalidated?(tracker, underlying_ltp, invalidation_price)
            return { exit: true, reason: "STRUCTURE_INVALIDATION (Price #{underlying_ltp} breached level #{invalidation_price})", path: 'structure_invalidation' }
          end
        end

        nil
      end

      def structure_invalidated?(tracker, underlying_ltp, invalidation_price)
        direction = tracker.meta&.dig('direction')&.to_s
        level = invalidation_price.to_f
        buffer = (level * 0.002).abs
        case direction
        when 'long_pe', 'bearish'
          underlying_ltp > level + buffer
        when 'long_ce', 'bullish'
          underlying_ltp < level - buffer
        else
          false
        end
      end

      def smc_navigator_exit_hit?(tracker, snapshot)
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        return false unless cfg[:enabled]
        return false unless defined?(Smc::Navigator)

        nav_result = Smc::Navigator.evaluate_exit(tracker, snapshot) rescue nil
        return false unless nav_result&.suggest_exit?

        min_conf = (cfg[:min_confidence] || 0.6).to_f
        nav_result.confidence.to_f >= min_conf
      end

      def adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers, tightening_multiplier: 1.0)
        return false if peak_profit_pct <= 0 || adaptive_tiers.blank?

        hwm = snapshot[:hwm_pnl].to_f
        pnl = snapshot[:pnl].to_f
        return false if hwm.zero?

        sorted_tiers = adaptive_tiers.sort_by { |t| -t[:min_profit].to_f }
        tier = sorted_tiers.find { |t| peak_profit_pct >= t[:min_profit].to_f }
        return false unless tier

        allowed_dd = (tier[:drawdown] || tier[:max_drawdown]).to_f
        return false unless allowed_dd.positive?

        effective_dd = allowed_dd * tightening_multiplier.to_f
        allowed_drop_from_hwm = effective_dd / peak_profit_pct
        current_drop = (hwm - pnl) / hwm

        current_drop >= allowed_drop_from_hwm
      end

      def evaluate_trailing_stop(tracker, snapshot)
        config = exit_config
        return nil unless config[:trailing][:enabled]

        ltp = snapshot[:ltp].to_f
        return nil unless ltp.positive?

        tightening_mult = 1.0
        if trailing_armed?(tracker, snapshot, config)
          ctx_res = evaluate_underlying_context(tracker, snapshot) rescue nil
          if ctx_res.is_a?(Hash)
            if ctx_res[:action] == :exit
              return { exit: true, reason: ctx_res[:reason] || 'UNDERLYING_STRUCTURE_BREAK', path: 'underlying_context_exit' }
            elsif ctx_res[:action] == :tighten
              tightening_mult = ctx_res[:multiplier].to_f
            end
          end
        end

        if trailing_stop_hit?(tracker, snapshot, tightening_multiplier: tightening_mult)
          return { exit: true, reason: 'TRAILING_STOP', path: 'trailing_stop' }
        end

        nil
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

        hwm = snapshot[:hwm_pnl].to_f
        return false if hwm.zero?
        pnl_pct = snapshot[:pnl_pct].to_f
        return false if pnl_pct <= 0

        drop_threshold = config[:trailing][:drop_threshold].to_f
        pnl = snapshot[:pnl].to_f
        (hwm - pnl) / hwm >= drop_threshold
      end

      # Best-effort trailing SL price for DISPLAY only — mirrors trailing_stop_hit?'s
      # logic without ever triggering an exit. Returns nil when trailing hasn't armed
      # yet, or when the active rule is PnL-ratio-based and no reliable price
      # equivalent can be derived (falls back to the caller's static SL in that case).
      def live_sl_price(tracker, snapshot, ltp)
        return nil unless snapshot && ltp.to_f.positive?

        config = exit_config
        return nil unless config[:trailing][:enabled]

        qty = tracker.quantity.to_f
        return nil unless qty.positive?

        symbol = tracker.symbol.to_s.upcase
        if %w[NIFTY BANKNIFTY SENSEX].any? { |s| symbol.include?(s) }
          live_sl_price_for_index(tracker, snapshot, ltp, config)
        else
          hwm = snapshot[:hwm_pnl].to_f
          return nil if hwm <= 0

          pnl_floor = hwm * (1.0 - config[:trailing][:drop_threshold].to_f)
          implied_price_from_pnl_floor(tracker, snapshot, ltp, pnl_floor)
        end
      rescue StandardError => e
        Rails.logger.debug { "[UnifiedExitChecker] live_sl_price failed for #{tracker.id}: #{e.class} - #{e.message}" }
        nil
      end

      def live_sl_price_for_index(tracker, snapshot, ltp, config)
        entry_value = tracker.entry_price.to_f * tracker.quantity.to_f
        return nil unless entry_value.positive?

        activation = config[:trailing][:activation_profit].to_f
        peak_profit_pct = snapshot[:hwm_pnl].to_f / entry_value
        return nil if activation.positive? && peak_profit_pct < activation

        index_key = tracker.meta&.dig('index_key')&.downcase
        inst_trailing = AlgoConfig.fetch.dig(:risk, :institutional_trailing, index_key&.to_sym) || {}
        adaptive_tiers = inst_trailing[:adaptive_drawdown]

        if adaptive_tiers.is_a?(Array) && adaptive_tiers.any?
          return implied_sl_from_drawdown_tiers(tracker, snapshot, ltp, peak_profit_pct, adaptive_tiers)
        end

        pos_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        prices = pos_data&.price_history || [ltp]
        analyzer = Orders::Analyzer.new(tracker: tracker, ltp: ltp, prices: prices, peak_profit_pct: peak_profit_pct)
        analyzer.recommended_sl
      end

      def implied_sl_from_drawdown_tiers(tracker, snapshot, ltp, peak_profit_pct, adaptive_tiers)
        sorted_tiers = adaptive_tiers.sort_by { |t| -t[:min_profit].to_f }
        tier = sorted_tiers.find { |t| peak_profit_pct >= t[:min_profit].to_f }
        return nil unless tier

        allowed_dd = (tier[:drawdown] || tier[:max_drawdown]).to_f
        return nil unless allowed_dd.positive?

        hwm = snapshot[:hwm_pnl].to_f
        return nil if hwm <= 0

        allowed_drop_from_hwm = allowed_dd / peak_profit_pct
        pnl_floor = hwm * (1.0 - allowed_drop_from_hwm)
        implied_price_from_pnl_floor(tracker, snapshot, ltp, pnl_floor)
      end

      # The adaptive/simple trailing rules are expressed in PnL space (drop from peak
      # profit), not price space. PnL moves linearly with LTP at rate = quantity (fees
      # are a fixed offset that cancels out in a delta calc), so we back-solve the LTP
      # that would hit the target PnL floor instead of re-deriving the PnL formula here.
      def implied_price_from_pnl_floor(tracker, snapshot, ltp, pnl_floor)
        qty = tracker.quantity.to_f
        return nil unless qty.positive?

        delta_pnl_needed = snapshot[:pnl].to_f - pnl_floor
        (ltp.to_f - (delta_pnl_needed / qty)).round(2)
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

        return false if snapshot[:pnl_pct].to_f.positive?

        stall_minutes = (cfg[:stall_minutes] || 3).to_f
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
        begin
          (current_atr / avg_atr).round(3)
        rescue StandardError
          1.0
        end
      end

      def calculate_atr(candles)
        return 0.0 if candles.size < 2
        true_ranges = candles.each_cons(2).map { |p, c| [(c.high - c.low), (c.high - p.close).abs, (c.low - p.close).abs].max }
        true_ranges.sum / true_ranges.size
      end

      def build_position_data(tracker, _snapshot, instrument)
        series = begin
                   instrument.candle_series(interval: '5')
        rescue StandardError
                   nil
        end
        candles = series&.candles || []
        adx_value = begin
                      instrument.adx(14, interval: '5')
        rescue StandardError
                      nil
        end
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

        sl_value = risk_cfg[:sl_pct]
        sl_value_pct = sl_value ? sl_value.to_f : (exit_cfg.dig(:stop_loss, :value) || 0.12)

        tp_value = exit_cfg[:take_profit] || risk_cfg[:tp_pct] || 0.50

        trailing_activation = exit_cfg.dig(:trailing, :activation_profit) || risk_cfg.dig(:trailing, :activation_pct) || 0.035
        trailing_drop = exit_cfg.dig(:trailing, :drop_threshold) || risk_cfg.dig(:trailing, :drawdown_pct) || 0.025

        {
          stop_loss: {
            type: exit_cfg.dig(:stop_loss, :type) || 'static',
            value: sl_value_pct
          },
          take_profit: tp_value.to_f,
          trailing: {
            enabled: exit_cfg.dig(:trailing, :enabled) != false,
            type: exit_cfg.dig(:trailing, :type) || 'adaptive',
            activation_profit: trailing_activation.to_f,
            drop_threshold: trailing_drop.to_f
          },
          early_exit: {
            enabled: exit_cfg.dig(:early_exit, :enabled) != false,
            profit_threshold: (exit_cfg.dig(:early_exit, :profit_threshold) || 0.07).to_f
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
          stop_loss: { type: 'static', value: 0.12 },
          take_profit: 0.50,
          trailing: { enabled: true, type: 'adaptive', activation_profit: 0.035, drop_threshold: 0.025 },
          early_exit: { enabled: true, profit_threshold: 0.07 },
          premium_momentum_failure: { enabled: true },
          time_based: { enabled: false, exit_time: '15:20' }
        }
      end
    end
  end
end
