# frozen_string_literal: true

module Signal
  module Engines
    class SwingOptionBuyingEngine < BaseEngine
      def evaluate
        tick = option_tick
        return unless tick

        return unless tick[:htf_supertrend].to_s.casecmp('up').zero?

        ltp = tick[:ltp].to_f
        ema9 = tick[:ema9].to_f
        ema21 = tick[:ema21].to_f
        prev_high = tick[:prev_high].to_f

        return unless ema9.positive? && ema21.positive?
        return unless ltp < ema9 && ltp > ema21
        return unless prev_high.positive? && ltp > prev_high

        create_signal(
          reason: 'Swing trend continuation',
          meta: {
            ema_position: 'between_ema9_ema21',
            above_prev_high: true
          }
        )
      end
    end
  end
end
