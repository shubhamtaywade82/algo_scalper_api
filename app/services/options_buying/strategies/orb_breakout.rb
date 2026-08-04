# frozen_string_literal: true

module OptionsBuying
  module Strategies
    class OrbBreakout < BaseStrategy
      def check_entry(market_state)
        # ORB requires index typical time is past the orb period
        return nil unless orb_period_completed?

        # We only trade ORB in a short window after it forms (e.g. 09:30 - 10:30)
        current_time = Time.current.strftime('%H:%M')
        return nil if current_time > orb_valid_until

        range = calculate_opening_range
        return nil unless range

        spot_ltp = market_state[:spot_ltp]
        direction = determine_breakout_direction(spot_ltp, range)
        return nil unless direction

        # Check volume confirmation
        return nil unless volume_confirmed?(direction, range)

        # Select option
        radar = StateStore.radar_strikes(@index_key)
        option_type = direction == :bullish ? 'CE' : 'PE'
        target_strike = radar.find { |s| s[:type] == option_type }
        return nil unless target_strike

        metrics = {
          direction: direction,
          spot_ltp: spot_ltp,
          range_high: range[:high],
          range_low: range[:low]
        }

        sink_telemetry!(direction: direction, option_security_id: target_strike[:security_id], metrics: metrics)

        {
          direction: direction,
          option_security_id: target_strike[:security_id],
          metrics: metrics
        }
      end

      def name
        'orb_breakout'
      end

      def required_regime
        :trending
      end

      private

      def period_minutes
        (config[:period_minutes] || 15).to_i
      end

      def volume_multiplier
        (config[:volume_multiplier] || 1.5).to_f
      end

      def orb_period_completed?
        market_open = Time.zone.now.beginning_of_day + 9.hours + 15.minutes
        Time.current >= (market_open + period_minutes.minutes)
      end

      def orb_valid_until
        # Hardcode 1 hour after ORB finishes, or configurable
        market_open = Time.zone.now.beginning_of_day + 9.hours + 15.minutes
        (market_open + period_minutes.minutes + 1.hour).strftime('%H:%M')
      end

      def calculate_opening_range
        # Use pre-computed cached 1m candles
        candles = StateStore.index_candles(@index_key, '1')
        return nil if candles.blank?

        today_start = Time.zone.now.beginning_of_day + 9.hours + 15.minutes
        orb_end = today_start + period_minutes.minutes

        orb_candles = candles.select do |c|
          ts = Time.zone.parse(c[:timestamp])
          ts >= today_start && ts < orb_end
        end

        return nil if orb_candles.empty?

        high = orb_candles.map { |c| c[:high].to_f }.max
        low = orb_candles.map { |c| c[:low].to_f }.min
        avg_volume = orb_candles.sum { |c| c[:volume].to_f } / orb_candles.size

        { high: high, low: low, avg_volume: avg_volume }
      end

      def determine_breakout_direction(spot_ltp, range)
        return :bullish if spot_ltp > range[:high]
        return :bearish if spot_ltp < range[:low]
        nil
      end

      def volume_confirmed?(direction, range)
        # Use pre-computed cached 1m candles
        candles = StateStore.index_candles(@index_key, '1')
        return false if candles.blank?

        current_candle_vol = candles.last[:volume].to_f
        current_candle_vol > (range[:avg_volume] * volume_multiplier)
      end

      def index_sid
        IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }&.dig(:sid).to_s
      end
    end
  end
end
