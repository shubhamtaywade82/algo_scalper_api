# frozen_string_literal: true

module Risk
  module Rules
    # Prop-desk adaptive option-premium trail with staged giveback bands.
    class AdaptiveTrailRule < BaseRule
      PRIORITY = 25

      DEFAULT_STAGES = [
        { min_profit: 0.0, trail_behind_peak: 0.40, hard_stop: -0.30, name: 'entry_guard' },
        { min_profit: 0.20, trail_behind_peak: 0.35, hard_stop: nil, name: 'momentum_ride' },
        { min_profit: 0.60, trail_behind_peak: 0.28, hard_stop: nil, name: 'profit_lock' },
        { min_profit: 1.20, trail_behind_peak: 0.22, hard_stop: nil, name: 'runner_mode' }
      ].freeze

      LONG_DIRECTIONS = %w[bullish long long_ce call ce].freeze
      SHORT_DIRECTIONS = %w[bearish short long_pe put pe].freeze

      def evaluate(context)
        return skip_result unless context.active?
        return no_action_result if disabled?

        override = override_exit(context)
        return override if override

        entry = context.tracker.entry_price.to_f
        ltp = context.current_ltp.to_f
        return skip_result unless entry.positive? && ltp.positive?

        peak = peak_premium(context, entry, ltp)
        peak_profit_pct = (peak - entry) / entry
        current_profit_pct = (ltp - entry) / entry
        stage = stage_for(peak_profit_pct)

        hard_stop = stage[:hard_stop]
        if hard_stop && current_profit_pct <= hard_stop.to_f
          return exit_result(
            reason: 'ADAPTIVE_TRAIL_HARD_STOP',
            metadata: metadata(stage, ltp, peak, entry, trail_price: entry * (1.0 + hard_stop.to_f))
          )
        end

        peak_gain = peak - entry
        return no_action_result if peak_gain <= 0

        trail_price = trail_price_for(entry: entry, peak: peak, stage: stage)
        return no_action_result if ltp > trail_price

        exit_result(
          reason: 'ADAPTIVE_TRAIL',
          metadata: metadata(stage, ltp, peak, entry, trail_price: trail_price)
        )
      end

      def enabled?(_context = nil)
        !disabled?
      end

      private

      def disabled?
        adaptive_config[:enabled] == false
      end

      def adaptive_config
        config.dig(:risk, :adaptive_trailing) || config[:adaptive_trailing] || {}
      end

      def stage_for(peak_profit_pct)
        configured = Array(adaptive_config[:stages]).presence || DEFAULT_STAGES
        configured
          .map(&:deep_symbolize_keys)
          .select { |stage| peak_profit_pct >= stage[:min_profit].to_f }
          .max_by { |stage| stage[:min_profit].to_f } || DEFAULT_STAGES.first
      end

      def peak_premium(context, entry, ltp)
        snapshot = context.tracker_snapshot || {}
        qty = [context.tracker.quantity.to_i, 1].max
        hwm_peak = entry + (snapshot[:hwm_pnl].to_f / qty)
        meta_peak = context.tracker.peak_premium.to_f
        [entry, ltp, hwm_peak, meta_peak].max
      end

      def trail_price_for(entry:, peak:, stage:)
        peak_gain = peak - entry
        peak - (peak_gain * stage[:trail_behind_peak].to_f)
      end

      def override_exit(context)
        return supertrend_exit(context) if supertrend_flipped?(context)
        return counter_candle_exit(context) if counter_candles?(context)

        nil
      end

      def supertrend_flipped?(context)
        return false unless adaptive_config.fetch(:supertrend_flip_exit, true)

        direction = context.tracker.direction.to_s
        series = underlying_series(context, '1')
        return false unless direction.present? && series&.candles&.any?

        st_cfg = AlgoConfig.fetch.dig(:signals, :supertrend) || {}
        st = Indicators::Supertrend.new(series: series, **st_cfg).call
        current = SupertrendTrend.direction(series: series, supertrend_result: st)
        long_trade?(direction) ? current == :short : current == :long
      rescue StandardError => e
        Rails.logger.warn("[AdaptiveTrailRule] supertrend override unavailable: #{e.class} #{e.message}")
        false
      end

      def counter_candles?(context)
        needed = adaptive_config.fetch(:counter_candles, 3).to_i
        return false unless needed.positive?

        direction = context.tracker.direction.to_s
        candles = underlying_series(context, '1')&.candles&.last(needed)
        return false unless direction.present? && candles&.size == needed

        long_trade?(direction) ? candles.all?(&:bearish?) : candles.all?(&:bullish?)
      rescue StandardError => e
        Rails.logger.warn("[AdaptiveTrailRule] counter-candle override unavailable: #{e.class} #{e.message}")
        false
      end

      def long_trade?(direction)
        LONG_DIRECTIONS.include?(direction.to_s.downcase)
      end

      def underlying_series(context, interval)
        index_key = context.tracker.index_key
        instrument = context.tracker.instrument || context.tracker.watchable
        return instrument&.candle_series(interval: interval) unless index_key

        Instrument.find_by(symbol_name: index_key.to_s.upcase)&.candle_series(interval: interval) ||
          instrument&.candle_series(interval: interval)
      end

      def supertrend_exit(context)
        exit_result(reason: 'SUPERTREND_FLIP_EXIT', metadata: { path: 'supertrend_flip', tracker_id: context.tracker.id })
      end

      def counter_candle_exit(context)
        exit_result(reason: 'COUNTER_CANDLE_EXIT', metadata: { path: 'counter_candles', tracker_id: context.tracker.id })
      end

      def metadata(stage, ltp, peak, entry, trail_price:)
        {
          path: 'adaptive_trail',
          stage: stage[:name].to_s,
          ltp: ltp.round(2),
          peak_premium: peak.round(2),
          trail_price: trail_price.round(2),
          peak_profit_pct: (((peak - entry) / entry) * 100.0).round(2)
        }
      end
    end
  end
end
