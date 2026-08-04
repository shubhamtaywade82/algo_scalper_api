# frozen_string_literal: true

module Risk
  module Rules
    # Rule for detection of early trend failure before profit target is reached.
    # Matches logic from UnifiedExitChecker#early_exit_triggered?
    class EarlyTrendFailureRule < BaseRule
      PRIORITY = 10 # High priority but below emergency logic

      def evaluate(context)
        tracker = context.tracker
        snapshot = context.tracker_snapshot
        return skip_result unless tracker && snapshot

        # Delegate to legacy method for parity and spec compatibility
        if Live::UnifiedExitChecker.early_exit_triggered?(tracker, snapshot)
          return exit_result(
            reason: 'EARLY_TREND_FAILURE',
            metadata: {
              path: 'early_exit'
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[EarlyTrendFailureRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?(context = nil)
        # Always enabled if the system config allows it, but context-aware
        config.fetch(:enabled, true)
      end

      private

      def build_evaluator_data(tracker, snapshot, instrument)
        # Replicates the logic from UnifiedExitChecker#build_position_data
        series = begin
          instrument.candle_series(interval: '5')
        rescue StandardError
          nil
        end
        candles = series&.candles || []
        
        # LTP and ADX logic
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
          atr_ratio: calculate_atr_ratio(tracker, instrument),
          underlying_price: tracker.entry_price.to_f,
          vwap: candles.any? ? candles.last(20).sum(&:close) / [candles.last(20).size, 1].max : tracker.entry_price.to_f,
          is_long?: %w[long_ce long_pe].include?(tracker.side),
          current_ltp: snapshot.current_ltp.to_f,
          pnl_pct: snapshot.pnl_pct.to_f
        )
      end

      def calculate_atr_ratio(tracker, instrument)
        # Basic logic from UnifiedExitChecker#calculate_atr_ratio
        return 1.0 unless instrument
        series = instrument.candle_series(interval: '5')
        return 1.0 if series.blank? || series.candles.blank?
        
        candles = series.candles.last(20)
        return 1.0 if candles.size < 10

        current_atr = calculate_atr(candles.last(14))
        avg_atr = calculate_atr(candles)
        return 1.0 unless current_atr.positive? && avg_atr.positive?

        (current_atr / avg_atr).round(3)
      rescue StandardError
        1.0
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
    end
  end
end
