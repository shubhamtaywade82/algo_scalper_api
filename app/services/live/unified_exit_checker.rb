# frozen_string_literal: true

# Unified Exit Checker - KISS Principle
# Single method that checks all exit conditions in priority order
module Live
  class UnifiedExitChecker
    class << self
      include Live::UnderlyingLtpResolver
      include Live::StructureInvalidationEvaluator
      include Live::UnderlyingContextEvaluator

      # Check all exit conditions and return first match
      # Returns: { exit: true/false, reason: "...", path: "..." } or nil
      def check_exit_conditions(tracker)
        snapshot = pnl_snapshot(tracker)
        return nil unless snapshot

        pnl_pct = snapshot[:pnl_pct].to_f * 100.0

        # Build RuleContext
        context = Risk::Rules::RuleContext.new(
          position: OpenStruct.new(
            current_ltp: snapshot[:ltp],
            pnl_pct: snapshot[:pnl_pct],
            pnl_rupees: snapshot[:pnl],
            high_water_mark: snapshot[:hwm_pnl],
            hwm_pnl: snapshot[:hwm_pnl],
            peak_profit_pct: peak_profit_pct_for(snapshot, tracker)
          ),
          tracker: tracker,
          tracker_snapshot: snapshot,
          risk_config: pinned_config
        )

        # 0. Portfolio Floor Breach (highest priority — overrides all per-position logic)
        if portfolio_floor_breach?
          return {
            exit: true,
            reason: 'PORTFOLIO_FLOOR_BREACH',
            path: 'profit_lock',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 1. Early Trend Failure (if enabled and applicable)
        if early_exit_triggered?(tracker, snapshot)
          return {
            exit: true,
            reason: 'EARLY_TREND_FAILURE',
            path: 'early_trend_failure',
            pnl_pct: pnl_pct
          }
        end

        # 2. Loss Limit (stop loss)
        if loss_limit_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'STOP_LOSS',
            path: 'stop_loss',
            pnl_pct: pnl_pct
          }
        end

        # 3. Profit Target (take profit)
        if profit_target_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'TAKE_PROFIT',
            path: 'take_profit',
            pnl_pct: pnl_pct
          }
        end

        # 3.5 Percentage PnL Exit (safety net — only when trailing failed to arm, works in tick-first mode)
        if percentage_pnl_exit_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: "PERCENTAGE_PNL_EXIT (#{(pnl_pct * 100.0).round(2)}%)",
            path: 'percentage_pnl_exit',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 4. Premium Momentum Failure (if enabled)
        if premium_momentum_failure_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'PREMIUM_MOMENTUM_FAILURE',
            path: 'premium_momentum_failure',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 5. Trailing Stop — underlying-context-aware
        underlying_ctx = evaluate_underlying_context(tracker, snapshot)
        if underlying_ctx[:action] == :exit
          return {
            exit: true,
            reason: underlying_ctx[:reason],
            path: 'underlying_context_exit',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        if trailing_stop_hit?(tracker, snapshot, tightening_multiplier: underlying_ctx[:multiplier])
          return {
            exit: true,
            reason: 'TRAILING_STOP',
            path: 'trailing_stop',
            pnl_pct: pnl_pct
          }
        end

        # 6. Structure Invalidation (options-aware dual condition)
        si_result = check_structure_invalidation(tracker, snapshot)
        return si_result.merge(pnl_pct: (pnl_pct * 100.0).round(2)) if si_result

        # 6.5 SMC Navigator Exit (LTF CHoCH / liquidity sweep against position)
        smc_nav_result = check_smc_navigator_exit(tracker, snapshot)
        return smc_nav_result.merge(pnl_pct: (pnl_pct * 100.0).round(2)) if smc_nav_result

        # 7. Time-Based Exit (if configured)
        if time_based_exit?(tracker)
          return {
            exit: true,
            reason: 'TIME_BASED',
            path: 'time_based',
            pnl_pct: pnl_pct
          }
        end

        nil # No exit needed
      end

      private

      def pnl_snapshot(tracker)
        Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
      rescue StandardError
        nil
      end

      # True if the portfolio profit floor has been breached today (DrawdownGuard has fired).
      # This is the highest-priority exit signal — overrides all per-position logic.
      def portfolio_floor_breach?
        Portfolio::DrawdownGuard.triggered?
      rescue StandardError
        false
      end

      def early_exit_triggered?(tracker, snapshot)
        config = exit_config
        return false unless config[:early_exit][:enabled]

        pnl_pct = snapshot[:pnl_pct].to_f * 100.0
        threshold = config[:early_exit][:profit_threshold].to_f
        return false if pnl_pct >= threshold

        # Check ETF conditions
        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument

        position_data = build_position_data(tracker, snapshot, instrument)
        Live::EarlyTrendFailure.early_trend_failure?(position_data)
      end

      def loss_limit_hit?(tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f * 100.0

        # Dynamic reverse SL (if enabled and below entry)
        if pnl_pct.negative? && config[:stop_loss][:type] == 'adaptive'
          seconds_below = seconds_below_entry(tracker)
          atr_ratio = calculate_atr_ratio(tracker)

          allowed_loss = Positions::DrawdownSchedule.reverse_dynamic_sl_pct(
            pnl_pct,
            seconds_below_entry: seconds_below,
            atr_ratio: atr_ratio
          )

          return true if allowed_loss && pnl_pct <= -allowed_loss
        end

        # Static stop loss
        static_sl = config[:stop_loss][:value].to_f
        pnl_pct <= -static_sl
      end

      # Fires only when trailing has NOT armed — pure fallback for when trailing fails to engage.
      # Once trailing is armed it manages the position; we must not cut the runner short here.
      def percentage_pnl_exit_hit?(tracker, snapshot)
        cfg = AlgoConfig.fetch.dig(:risk, :percentage_pnl_exit) || {}
        return false unless cfg[:enabled]

        target = cfg[:target_pct].to_f
        return false unless target.positive?

        pnl_pct = snapshot[:pnl_pct].to_f
        return false unless pnl_pct >= target

        # Suppress when trailing is already managing the position (same guard as profit_target_hit?)
        return false if trailing_armed?(tracker, snapshot, exit_config)

        true
      rescue StandardError
        false
      end

      def profit_target_hit?(tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f * 100.0
        tp = config[:take_profit].to_f

        pnl_pct >= tp
      end

      def trailing_stop_hit?(tracker, snapshot, tightening_multiplier: 1.0)
        config = exit_config
        return false unless config[:trailing][:enabled]

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

          # Adaptive drawdown from institutional trailing config (options-aware)
          index_key = tracker.meta&.dig('index_key')&.downcase
          inst_trailing = AlgoConfig.fetch.dig(:risk, :institutional_trailing, index_key&.to_sym) || {}
          adaptive_tiers = inst_trailing[:adaptive_drawdown]

          return true if adaptive_tiers.is_a?(Array) &&
                         adaptive_tiers.any? &&
                         adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers,
                                                 tightening_multiplier: tightening_multiplier)

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

            reason = mfe_sl && sl_price == mfe_sl ? 'MFE_RETRACE_EXIT' : 'GAMMA_AWARE_TRAILING'

            Rails.logger.info("[UnifiedExitChecker] #{reason} hit for #{tracker.order_no}: ltp=#{ltp}, sl=#{sl_price}")
            return true
          end
          return false
        end

        # Fallback to legacy trailing for other instruments
        pnl = snapshot[:pnl]
        hwm = snapshot[:hwm_pnl]
        return false if hwm.nil? || hwm.zero?

        pnl_pct = snapshot[:pnl_pct].to_f * 100.0
        return false if pnl_pct <= 0

        # Adaptive trailing (if enabled)
        if config[:trailing][:type] == 'adaptive'
          peak_profit_pct = (hwm / (tracker.entry_price.to_f * tracker.quantity.to_i)) * 100.0
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

        # Fixed trailing
        drop_threshold = config[:trailing][:drop_threshold].to_f
        drop_pct = (hwm - pnl) / hwm
        drop_pct >= drop_threshold
      end

      def time_based_exit?(_tracker)
        config = exit_config
        return false unless config[:time_based][:enabled]

        exit_time = Time.zone.parse(config[:time_based][:exit_time])
        return false unless exit_time

        Time.current >= exit_time
      end

      def seconds_below_entry(tracker)
        cache_key = "position:below_entry:#{tracker.id}"
        cached = Rails.cache.read(cache_key)

        snapshot = pnl_snapshot(tracker)
        return 0 unless snapshot

        pnl_pct = snapshot[:pnl_pct]
        return 0 if pnl_pct.nil? || pnl_pct >= 0

        Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
        if cached
          (Time.current - cached).to_i
        else
          0
        end
      rescue StandardError
        0
      end

      def calculate_atr_ratio(tracker)
        instrument = tracker.instrument || tracker.watchable&.instrument
        return 1.0 unless instrument

        begin
          series = instrument.candle_series(interval: '5')
          return 1.0 unless series&.candles&.any?

          candles = series.candles.last(20)
          return 1.0 if candles.size < 10

          current_atr = calculate_atr(candles.last(14))
          avg_atr = calculate_atr(candles)
          return 1.0 unless current_atr.positive? && avg_atr.positive?

          (current_atr / avg_atr).round(3)
        rescue StandardError
          1.0
        end
      end

      def calculate_atr(candles)
        return 0.0 if candles.size < 2

        true_ranges = []
        candles.each_cons(2) do |prev, curr|
          tr1 = curr.high - curr.low
          tr2 = (curr.high - prev.close).abs
          tr3 = (curr.low - prev.close).abs
          true_ranges << [tr1, tr2, tr3].max
        end

        return 0.0 if true_ranges.empty?

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
        @exit_config ||= begin
          cfg = AlgoConfig.fetch[:exit] || {}
          {
            stop_loss: {
              type: cfg.dig(:stop_loss, :type) || 'static',
              value: cfg.dig(:stop_loss, :value) || 3.0
            },
            take_profit: cfg[:take_profit] || 5.0,
            trailing: {
              enabled: cfg.dig(:trailing, :enabled) != false,
              type: cfg.dig(:trailing, :type) || 'adaptive',
              activation_profit: cfg.dig(:trailing, :activation_profit) || 3.0,
              drop_threshold: cfg.dig(:trailing, :drop_threshold) || 3.0
            },
            early_exit: {
              enabled: cfg.dig(:early_exit, :enabled) != false,
              profit_threshold: cfg.dig(:early_exit, :profit_threshold) || 7.0
            },
            time_based: {
              enabled: cfg.dig(:time_based, :enabled) == true,
              exit_time: cfg.dig(:time_based, :exit_time) || '15:20'
            }
          }
        rescue StandardError
          default_exit_config
        end
      end

      def default_exit_config
        {
          stop_loss: { type: 'static', value: 3.0 },
          take_profit: 5.0,
          trailing: { enabled: true, type: 'adaptive', activation_profit: 3.0, drop_threshold: 3.0 },
          early_exit: { enabled: true, profit_threshold: 7.0 },
          time_based: { enabled: false, exit_time: '15:20' }
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
        return unless smc_navigator_exit_enabled? && smc_navigator_min_hold_elapsed?(tracker)

        instrument = tracker.instrument
        return unless instrument

        ltp = snapshot[:ltp].to_f
        return unless ltp.positive?

        result = Smc::Navigator.evaluate_exit(tracker: tracker, ltp: ltp, instrument: instrument)
        return unless result.suggest_exit?
        return unless result.confidence >= smc_navigator_min_exit_confidence

        {
          exit: true,
          reason: "SMC_NAVIGATOR_EXIT (#{result.reason})",
          path: 'smc_navigator'
        }
      rescue StandardError => e
        Rails.logger.error("[UnifiedExitChecker] SMC navigator exit check failed: #{e.class} - #{e.message}")
        nil
      end

      def smc_navigator_exit_enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        cfg[:enabled] == true
      rescue StandardError
        false
      end

      def smc_navigator_min_hold_elapsed?(tracker)
        return false unless tracker.created_at

        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        min_seconds = (cfg[:min_hold_seconds] || 120).to_i
        (Time.current - tracker.created_at) >= min_seconds
      rescue StandardError
        false
      end

      def smc_navigator_min_exit_confidence
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        (cfg[:min_confidence] || 0.65).to_f
      rescue StandardError
        0.65
      end

      def check_smc_navigator_exit(tracker, snapshot)
        return unless smc_navigator_exit_enabled? && smc_navigator_min_hold_elapsed?(tracker)

        instrument = tracker.instrument
        return unless instrument

        ltp = snapshot[:ltp].to_f
        return unless ltp.positive?

        result = Smc::Navigator.evaluate_exit(tracker: tracker, ltp: ltp, instrument: instrument)
        return unless result.suggest_exit?
        return unless result.confidence >= smc_navigator_min_exit_confidence

        {
          exit: true,
          reason: "SMC_NAVIGATOR_EXIT (#{result.reason})",
          path: 'smc_navigator'
        }
      rescue StandardError => e
        Rails.logger.error("[UnifiedExitChecker] SMC navigator exit check failed: #{e.class} - #{e.message}")
        nil
      end

      def smc_navigator_exit_enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        cfg[:enabled] == true
      rescue StandardError
        false
      end

      def smc_navigator_min_hold_elapsed?(tracker)
        return false unless tracker.created_at

        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        min_seconds = (cfg[:min_hold_seconds] || 120).to_i
        (Time.current - tracker.created_at) >= min_seconds
      rescue StandardError
        false
      end

      def smc_navigator_min_exit_confidence
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        (cfg[:min_confidence] || 0.65).to_f
      rescue StandardError
        0.65
      end

      def structure_invalidation_enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}
        cfg.fetch(:enabled, true)
      rescue StandardError
        true
      end

      def check_structure_invalidation(tracker, snapshot)
        cfg = Positions::ExitConfigResolver.for(tracker).dig(:risk, :exits, :structure_invalidation) || {}
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
        pct = (Positions::ExitConfigResolver.for(tracker).dig(:risk, :exits, :structure_invalidation, :buffer_pct) || 0.002).to_f
        buffer = (level * pct).abs
        direction == 'long_pe' ? underlying_ltp > level + buffer : (direction == 'long_ce' ? underlying_ltp < level - buffer : false)
      end

      def peak_profit_pct_for(snapshot, tracker)
        return snapshot[:hwm_pnl_pct].to_f if snapshot[:hwm_pnl_pct]

        hwm = snapshot[:hwm_pnl].to_f
        return false unless hwm.positive?

        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return false unless entry_value.positive?

        peak_profit_pct = hwm / entry_value
        peak_profit_pct >= activation
      end

      def adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers, tightening_multiplier: 1.0)
        allowed_dd = Positions::TrailingConfig.adaptive_drawdown_for_peak(peak_profit_pct, adaptive_tiers)
        return false unless allowed_dd && peak_profit_pct.positive?

      def resolve_stall_minutes(tracker)
        pmf_cfg = Positions::ExitConfigResolver.for(tracker).dig(:risk, :exits, :premium_momentum_failure) || {}
        default_stall = 3

        multiplier = tightening_multiplier || 1.0
        effective_allowed_dd = allowed_dd * multiplier.to_f

        # Convert fractional drop from HWM into profit-percent scale for comparison with allowed_dd
        drop_from_peak_pct = (hwm - pnl_value) / hwm * peak_profit_pct
        return false unless drop_from_peak_pct >= effective_allowed_dd

        Rails.logger.info(
          "[UnifiedExitChecker] ADAPTIVE_TRAILING hit for #{tracker.order_no}: " \
          "drop=#{(drop_from_peak_pct * 100).round(2)}% >= allowed=#{(effective_allowed_dd * 100).round(2)}% " \
          "(multiplier=#{multiplier.to_f})"
        )
        true
      end
    end
  end
end
