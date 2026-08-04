# frozen_string_literal: true

module BacktestEngine
  module Strategies
    class ExpiryTrendV1
      MAX_HOLD_MINUTES = 25
      SL_PCT           = 30
      TARGET_PCT       = 60
      TRAIL_TRIGGER    = 40
      STRENGTH_FLOOR   = 5

      # Step function on regime_strength = (effective_score - 50).abs
      # Higher strength = regime further from neutral → lower volume bar required
      SPIKE_CURVE = [
        [30, 1.05],
        [20, 1.2],
        [10, 1.4],
        [5,  1.8]
      ].freeze

      def initialize(context:)
        @context = context
      end

      def call
        return no_trade!("Weak regime")  unless regime_strong_enough?
        return no_trade!("No structure") unless tradable_structure?
        return no_trade!("No pullback")  unless pullback?

        if bullish_setup?
          build_trade(:call)
        elsif bearish_setup?
          build_trade(:put)
        else
          no_trade!("No setup")
        end
      end

      private

      attr_reader :context

      def effective_score
        @effective_score ||= begin
          base    = context[:regime_score].to_f
          iv_mod  = context[:iv_expansion].to_f
          htf_pen = htf_misaligned? ? -5.0 : 0.0
          (base + iv_mod + htf_pen).clamp(0.0, 100.0)
        end
      end

      def regime_strength
        return 0.0 if context[:regime_score].nil?
        (effective_score - 50.0).abs
      end

      def htf_misaligned?
        htf = context[:htf_bias]
        return false if htf.nil?

        htf != context[:structure]
      end

      def regime_strong_enough?
        regime_strength >= STRENGTH_FLOOR
      end

      def adaptive_spike_factor
        s = regime_strength
        SPIKE_CURVE.each { |threshold, factor| return factor if s >= threshold }
        raise "regime_strength #{s} below all SPIKE_CURVE thresholds — update SPIKE_CURVE or STRENGTH_FLOOR"
      end

      def tradable_structure?
        %i[bullish bearish].include?(context[:structure])
      end

      def pullback?
        context[:pullback]
      end

      def bullish_setup?
        context[:structure] == :bullish &&
          context[:volume_ratio].to_f >= adaptive_spike_factor
      end

      def bearish_setup?
        context[:structure] == :bearish &&
          context[:volume_ratio].to_f >= adaptive_spike_factor
      end

      def strike_mode
        iv = context[:iv]

        if context[:structure] == :bullish && iv && iv < 25
          :atm_plus_1
        elsif context[:structure] == :bearish && iv && iv < 25
          :atm_minus_1
        else
          :atm
        end
      end

      def build_trade(option_type)
        {
          action: :buy,
          option_type: option_type,
          strike: strike_mode,
          sl_pct: SL_PCT,
          target_pct: TARGET_PCT,
          trail: true,
          trail_trigger: TRAIL_TRIGGER,
          max_hold_minutes: MAX_HOLD_MINUTES
        }
      end

      def no_trade!(reason)
        { action: :skip, reason: reason }
      end
    end
  end
end
