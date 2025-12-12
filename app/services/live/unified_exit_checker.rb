# frozen_string_literal: true

# Unified Exit Checker - KISS Principle
# Single method that checks all exit conditions in priority order
module Live
  class UnifiedExitChecker
    class << self
      # Check all exit conditions and return first match
      # Returns: { exit: true/false, reason: "...", path: "..." } or nil
      def check_exit_conditions(tracker)
        snapshot = pnl_snapshot(tracker)
        return nil unless snapshot

        pnl_pct = snapshot[:pnl_pct].to_f * 100.0

        # Priority order (first match wins)

        # 1. Early Trend Failure (if enabled and applicable)
        if early_exit_triggered?(tracker, snapshot)
          return {
            exit: true,
            reason: "EARLY_TREND_FAILURE",
            path: "early_trend_failure",
            pnl_pct: pnl_pct
          }
        end

        # 2. Loss Limit (stop loss)
        if loss_limit_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: "STOP_LOSS",
            path: "stop_loss",
            pnl_pct: pnl_pct
          }
        end

        # 3. Profit Target (take profit)
        if profit_target_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: "TAKE_PROFIT",
            path: "take_profit",
            pnl_pct: pnl_pct
          }
        end

        # 4. Trailing Stop (if enabled)
        if trailing_stop_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: "TRAILING_STOP",
            path: "trailing_stop",
            pnl_pct: pnl_pct
          }
        end

        # 5. Time-Based Exit (if configured)
        if time_based_exit?(tracker)
          return {
            exit: true,
            reason: "TIME_BASED",
            path: "time_based",
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
        if pnl_pct < 0 && config[:stop_loss][:type] == 'adaptive'
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

      def profit_target_hit?(tracker, snapshot)
        config = exit_config
        pnl_pct = snapshot[:pnl_pct].to_f * 100.0
        tp = config[:take_profit].to_f

        pnl_pct >= tp
      end

      def trailing_stop_hit?(tracker, snapshot)
        config = exit_config
        return false unless config[:trailing][:enabled]

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

      def time_based_exit?(tracker)
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

        if cached
          Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
          (Time.current - cached).to_i
        else
          Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
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

      def build_position_data(tracker, snapshot, instrument)
        series = instrument.candle_series(interval: '5') rescue nil
        candles = series&.candles || []
        adx_value = instrument.adx(14, interval: '5') rescue nil
        adx_hash = adx_value.is_a?(Hash) ? adx_value : { value: adx_value }

        OpenStruct.new(
          trend_score: adx_hash[:value]&.to_f || 0,
          peak_trend_score: tracker.meta&.dig('peak_trend_score') || 0,
          adx: adx_hash[:value],
          atr_ratio: calculate_atr_ratio(tracker),
          underlying_price: tracker.entry_price.to_f,
          vwap: candles.any? ? candles.last(20).map(&:close).sum / candles.last(20).size : tracker.entry_price.to_f,
          is_long?: tracker.side == 'long_ce' || tracker.side == 'long_pe'
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
    end
  end
end
