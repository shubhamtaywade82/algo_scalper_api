# frozen_string_literal: true

# Unified Exit Checker - KISS Principle
# Single method that checks all exit conditions in priority order
module Live
  class UnifiedExitChecker
    EXIT_CONFIG_TTL = 30 # seconds — matches AlgoConfig.fetch TTL

    class << self
      # Returns: { exit: true/false, reason: "...", path: "..." } or nil
      def check_exit_conditions(tracker)
        snapshot = pnl_snapshot(tracker)
        return nil unless snapshot

        pinned_config = Positions::ExitConfigResolver.for(tracker)
        engine = Risk::Rules::RuleEngine.new(
          rules: Risk::Rules::RuleFactory.exit_rules(pinned_config)
        )

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

        result = engine.evaluate(context)
        return nil if result.nil? || result.no_action? || result.skip?

        {
          exit: true,
          reason: result.reason,
          path: result.metadata[:path] || result.rule_name,
          pnl_pct: (snapshot[:pnl_pct].to_f * 100.0).round(2)
        }
      end

      def pnl_snapshot(tracker)
        Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
      rescue StandardError
        nil
      end

      def exit_config_for(tracker)
        build_exit_config(Positions::ExitConfigResolver.for(tracker))
      end

      def exit_config
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return @exit_config if @exit_config && @exit_config_expires_at && now < @exit_config_expires_at

        @exit_config = build_exit_config(AlgoConfig.fetch)
        @exit_config_expires_at = now + EXIT_CONFIG_TTL
        @exit_config
      end

      def loss_limit_hit?(tracker, snapshot)
        config = exit_config_for(tracker)
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

      def peak_profit_pct_for(snapshot, tracker)
        return snapshot[:hwm_pnl_pct].to_f if snapshot[:hwm_pnl_pct]

        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return 0.0 unless entry_value.positive?

        snapshot[:hwm_pnl].to_f / entry_value
      end

      private

      def build_exit_config(algo_cfg = AlgoConfig.fetch)
        risk_cfg = algo_cfg[:risk] || {}
        exit_cfg = algo_cfg[:exit] || {}
        sl_value_pct = risk_cfg[:sl_pct] || exit_cfg.dig(:stop_loss, :value) || 0.12
        tp_value = exit_cfg[:take_profit] || risk_cfg[:tp_pct] || 0.50
        {
          stop_loss: { type: exit_cfg.dig(:stop_loss, :type) || 'static', value: sl_value_pct.to_f },
          take_profit: tp_value.to_f
        }
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
        (current_atr / avg_atr).round(3)
      rescue StandardError
        1.0
      end

      def calculate_atr(candles)
        return 0.0 if candles.size < 2

        true_ranges = candles.each_cons(2).map do |previous, current|
          [(current.high - current.low), (current.high - previous.close).abs, (current.low - previous.close).abs].max
        end
        true_ranges.sum / true_ranges.size
      end
    end
  end
end
