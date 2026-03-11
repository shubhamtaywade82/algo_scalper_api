# frozen_string_literal: true

# Unified Exit Checker - KISS Principle
# Single method that checks all exit conditions in priority order
module Live
  class UnifiedExitChecker
    EXIT_CONFIG_TTL = 30 # seconds — matches AlgoConfig.fetch TTL

    class << self
      # Check all exit conditions and return first match
      # Returns: { exit: true/false, reason: "...", path: "..." } or nil
      def check_exit_conditions(tracker)
        snapshot = pnl_snapshot(tracker)
        return nil unless snapshot

        # snapshot[:pnl_pct] is decimal (e.g. 0.05 for 5%)
        pnl_pct = snapshot[:pnl_pct].to_f

        # Priority order (first match wins)

        # 1. Early Trend Failure (if enabled and applicable)
        if early_exit_triggered?(tracker, snapshot)
          return {
            exit: true,
            reason: 'EARLY_TREND_FAILURE',
            path: 'early_trend_failure',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 2. Loss Limit (stop loss)
        if loss_limit_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'STOP_LOSS',
            path: 'stop_loss',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 3. Profit Target (take profit)
        if profit_target_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'TAKE_PROFIT',
            path: 'take_profit',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 4. Trailing Stop (if enabled)
        if trailing_stop_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'TRAILING_STOP',
            path: 'trailing_stop',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        # 5. Time-Based Exit (if configured)
        if time_based_exit?(tracker)
          return {
            exit: true,
            reason: 'TIME_BASED',
            path: 'time_based',
            pnl_pct: (pnl_pct * 100.0).round(2)
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

      def early_exit_triggered?(tracker, snapshot)
        config = exit_config
        return false unless config[:early_exit][:enabled]

        pnl_pct = snapshot[:pnl_pct].to_f
        threshold = config[:early_exit][:profit_threshold].to_f  # Already DECIMAL (e.g. 0.07)
        return false if pnl_pct >= threshold

        # Check ETF conditions
        instrument = tracker.instrument || tracker.watchable&.instrument
        return false unless instrument

        position_data = build_position_data(tracker, snapshot, instrument)
        Live::EarlyTrendFailure.early_trend_failure?(position_data)
      end

      def loss_limit_hit?(tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f # e.g. -0.0396 (DECIMAL format)

        # Dynamic reverse SL (if enabled and below entry)
        if pnl_pct.negative? && config[:stop_loss][:type] == 'adaptive'
          seconds_below = seconds_below_entry(tracker)
          atr_ratio = calculate_atr_ratio(tracker)

          # allowed_loss is DECIMAL from schedule (e.g. 0.10 for 10%)
          # Pass DECIMAL pnl_pct directly (DrawdownSchedule now uses DECIMAL)
          allowed_loss = Positions::DrawdownSchedule.reverse_dynamic_sl_pct(
            pnl_pct,
            seconds_below_entry: seconds_below,
            atr_ratio: atr_ratio
          )

          # Both pnl_pct and allowed_loss are DECIMAL: -0.0396 <= -0.10 (False)
          return true if allowed_loss && pnl_pct <= -allowed_loss
        end

        # Static stop loss (config value is DECIMAL, e.g. 0.12 for 12%)
        static_sl = config[:stop_loss][:value].to_f
        pnl_pct <= -static_sl
      end

      def profit_target_hit?(_tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f # DECIMAL format (e.g., 0.05 for 5%)
        tp = config[:take_profit].to_f # Already DECIMAL (e.g., 0.50 for 50%)

        pnl_pct >= tp
      end

      def trailing_stop_hit?(tracker, snapshot)
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

        # Adaptive trailing (if enabled)
        if config[:trailing][:type] == 'adaptive'
          # peak_profit_pct is DECIMAL (e.g. 0.20 for 20%)
          peak_profit_pct = (hwm / (tracker.entry_price.to_f * tracker.quantity.to_i))
          activation = config[:trailing][:activation_profit].to_f  # Already DECIMAL

          return false if peak_profit_pct < activation

          index_key = tracker.meta&.dig('index_key') || tracker.instrument&.symbol_name
          # Pass DECIMAL peak_profit_pct; returns DECIMAL allowed_dd
          allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(peak_profit_pct, index_key: index_key)

          if allowed_dd
            allowed_drop_from_hwm = allowed_dd / peak_profit_pct
            current_drop = (hwm - pnl) / hwm
            return current_drop >= allowed_drop_from_hwm
          end
        end

        # Fixed trailing
        drop_threshold = config[:trailing][:drop_threshold].to_f  # Already DECIMAL
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
          peak_trend_score: tracker.meta&.dig('peak_trend_score') || 0,
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
          time_based: { enabled: false, exit_time: '15:20' }
        }
      end
    end
  end
end
