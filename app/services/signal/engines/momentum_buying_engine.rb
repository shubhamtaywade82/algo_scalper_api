# frozen_string_literal: true

module Signal
  module Engines
    class MomentumBuyingEngine < BaseEngine
      def evaluate
        tick = option_tick
        return unless tick

        day_high = tick[:day_high].to_f
        ltp = tick[:ltp].to_f
        return if day_high.zero? || ltp <= day_high

        min_rsi = strategy_threshold(:min_rsi, nil)
        if min_rsi
          rsi = tick[:rsi].to_f
          return unless rsi.positive? && rsi > min_rsi.to_i
        end

        create_signal(
          reason: 'Momentum breakout',
          meta: {
            breakout_above_high: true,
            rsi: tick[:rsi]&.to_f
          }
        )
      end
    end
  end
end
