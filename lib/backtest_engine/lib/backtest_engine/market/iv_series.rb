module BacktestEngine
  module Market
    class IvSeries
      # option_candles: array of hashes from ExpiredOptionsData#to_candles
      def initialize(option_candles)
        @points = Array(option_candles).sort_by { |c| c[:timestamp] }
      end

      def iv_for(timestamp)
        target = timestamp.is_a?(Integer) ? timestamp : timestamp.to_i
        point = @points.find { |c| c[:timestamp].to_i == target }
        point && point[:iv].to_f
      end

      def iv_percentile(timestamp, window: 100)
        current_iv = iv_for(timestamp)
        return nil unless current_iv

        window_points = last_window(window)
        return nil if window_points.empty?

        sorted = window_points.map { |c| c[:iv].to_f }.sort
        index = sorted.index { |v| v >= current_iv } || (sorted.size - 1)
        ((index + 1).to_f / sorted.size) * 100.0
      end

      def readings_before(timestamp, n)
        target = timestamp.to_i
        qualifying = @points.select { |c| c[:timestamp].to_i < target }
        qualifying.last(n).map { |c| c[:iv].to_f }
      end

      private

      def last_window(window)
        return @points if @points.size <= window

        @points.last(window)
      end
    end
  end
end

