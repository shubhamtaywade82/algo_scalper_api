# frozen_string_literal: true

module OptionsBuying
  # Calculates VWAP using minute ticks for the current session.
  class VwapCalculator
    def initialize(index_key)
      @index_key = index_key.to_s.upcase
    end

    # Computes session VWAP for the given security ID
    def compute(security_id)
      # Minute ticks from state store are already aggregated per minute bucket
      # But state store might only keep recent buckets.
      # Alternatively, we could query CandleSeries for 1m candles for the current day.
      # Let's use CandleSeries for robustness as it covers the whole day.
      candles = Market::CandleSeries.new(
        security_id: security_id,
        segment: 'IDX_I', # Default segment, assuming we are computing VWAP for index or options
        timeframe: '1'
      ).fetch(limit: 375) # Max 1m candles in a day

      return calculate_from_candles(candles) if candles&.any?

      # Fallback to proxy
      nil
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
      today_candles = candles.select { |c| Time.zone.parse(c[:timestamp]) >= today_start }
      return nil if today_candles.empty?

      cumulative_pv = 0.0
      cumulative_v = 0.0

      today_candles.each do |c|
        high = c[:high].to_f
        low = c[:low].to_f
        close = c[:close].to_f
        volume = c[:volume].to_f

        typical_price = (high + low + close) / 3.0
        cumulative_pv += (typical_price * volume)
        cumulative_v += volume
      end

      return nil if cumulative_v.zero?

      cumulative_pv / cumulative_v
    end
  end
end
