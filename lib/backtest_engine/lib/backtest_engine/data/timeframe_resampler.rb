module BacktestEngine
  module Data
    class TimeframeResampler
      def self.resample(candles, interval_minutes)
        return [] unless candles.is_a?(Array) && interval_minutes.to_i.positive?

        candles.each_slice(interval_minutes.to_i).map do |group|
          {
            timestamp: group.first[:timestamp],
            open: group.first[:open],
            high: group.map { |c| c[:high] }.max,
            low: group.map { |c| c[:low] }.min,
            close: group.last[:close],
            volume: group.sum { |c| c[:volume] }
          }
        end
      end
    end
  end
end

