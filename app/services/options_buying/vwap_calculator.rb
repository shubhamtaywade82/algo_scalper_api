# frozen_string_literal: true

module OptionsBuying
  # Calculates VWAP using minute ticks for the current session.
  class VWAPCalculator
    def initialize(index_key)
      @index_key = index_key.to_s.upcase
    end

    # Computes session VWAP for the given security ID
    def compute(security_id)
      instrument = Instrument.find_by(security_id: security_id)
      return nil unless instrument

      raw = instrument.intraday_ohlc(interval: '1', days: 1)
      return nil if raw.blank?

      series = CandleSeries.new(symbol: @index_key, interval: '1')
      series.load_from_raw(raw)

      calculate_from_candles(series.candles)
    end

    def near_vwap?(price, vwap_value, tolerance_pct: 0.001)
      return false unless price&.positive? && vwap_value&.positive?

      diff = (price - vwap_value).abs
      diff <= (price * tolerance_pct)
    end

    private

    def calculate_from_candles(candles)
      # Filter for today's candles only
      today_start = Time.zone.now.beginning_of_day
      today_candles = candles.select { |c| c.timestamp >= today_start }
      return nil if today_candles.empty?

      cumulative_pv = 0.0
      cumulative_v = 0.0

      today_candles.each do |c|
        typical_price = (c.high + c.low + c.close) / 3.0
        cumulative_pv += (typical_price * c.volume)
        cumulative_v += c.volume
      end

      return nil if cumulative_v.zero?

      cumulative_pv / cumulative_v
    end
  end
end
