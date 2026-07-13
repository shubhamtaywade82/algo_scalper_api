# frozen_string_literal: true

module BacktestEngine
  module Market
    class IvExpansionSignal
      DEFAULT_PERIOD = 10

      def initialize(iv_series, period: DEFAULT_PERIOD)
        @iv_series = iv_series
        @period = period
      end

      def modifier_at(timestamp)
        return 0.0 if @iv_series.nil?

        current = @iv_series.iv_for(timestamp)
        return 0.0 if current.nil?

        readings = @iv_series.readings_before(timestamp, @period)
        return 0.0 if readings.size < @period

        rolling_avg = readings.sum / @period.to_f
        return 0.0 if rolling_avg.zero?

        delta_pct = ((current - rolling_avg) / rolling_avg) * 100.0
        delta_pct.clamp(-15.0, 15.0)
      end
    end
  end
end
