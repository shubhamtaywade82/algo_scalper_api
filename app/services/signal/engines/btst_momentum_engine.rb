# frozen_string_literal: true

module Signal
  module Engines
    class BtstMomentumEngine < BaseEngine
      EOD_MIN = '15:10'
      EOD_MAX = '15:20'

      def evaluate
        return unless eod_window?

        tick = option_tick
        return unless tick

        ltp = tick[:ltp].to_f
        vwap = tick[:vwap].to_f
        volume = tick[:volume].to_i
        avg_volume = tick[:avg_volume].to_i

        return unless ltp.positive? && vwap.positive? && ltp > vwap
        return unless volume.positive? && avg_volume.positive? && volume > avg_volume

        create_signal(
          reason: 'BTST momentum',
          meta: {
            vwap_premium: ((ltp - vwap) / vwap * 100).round(2),
            volume_ratio: (volume.to_f / avg_volume).round(2)
          }
        )
      end

      private

      def eod_window?
        now = Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
        now >= EOD_MIN && now <= EOD_MAX
      end
    end
  end
end
