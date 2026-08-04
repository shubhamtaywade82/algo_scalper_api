# frozen_string_literal: true

module Signal
  module Engines
    class OpenInterestBuyingEngine < BaseEngine
      def evaluate
        tick = option_tick
        return unless tick

        current_oi = tick[:oi].to_i
        prev_close = tick[:prev_close].to_f
        price = tick[:ltp].to_f

        return if current_oi.zero? || prev_close.zero?

        last_oi = state_get(:last_oi, current_oi)
        state_set(:last_oi, current_oi)

        return unless current_oi > last_oi
        return unless price > prev_close

        create_signal(
          reason: 'OI buildup',
          meta: {
            oi_change: current_oi - last_oi,
            price_change_pct: ((price - prev_close) / prev_close * 100).round(2)
          }
        )
      end
    end
  end
end
