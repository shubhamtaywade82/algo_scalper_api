# frozen_string_literal: true

module OptionsBuying
  class TickMetrics
    class << self
      def volume_delta(ticks)
        return 0 if ticks.blank?

        volumes = ticks.map { |t| tick_volume(t) }
        return 0 if volumes.size < 2

        delta = volumes.last - volumes.first
        delta.positive? ? delta : 0
      end

      def oi_delta(ticks)
        return 0 if ticks.blank?

        oi_values = ticks.map { |t| tick_oi(t) }
        return 0 if oi_values.size < 2

        oi_values.last - oi_values.first
      end

      def mean_interval_volume_delta(ticks, min_samples: 3)
        return nil if ticks.blank? || ticks.size < 2

        deltas = ticks.each_cons(2).map do |first, second|
          delta = tick_volume(second) - tick_volume(first)
          delta.positive? ? delta : 0
        end
        positive = deltas.select(&:positive?)
        return nil if positive.size < min_samples

        positive.sum / positive.size.to_f
      end

      def close_price(ticks)
        tick_ltp(ticks&.last).to_f
      end

      private

      def tick_volume(tick)
        (tick[:vol] || tick[:volume]).to_i
      end

      def tick_oi(tick)
        tick[:oi].to_i
      end

      def tick_ltp(tick)
        tick[:ltp].to_f
      end
    end
  end
end
