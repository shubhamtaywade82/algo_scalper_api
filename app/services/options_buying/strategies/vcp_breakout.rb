# frozen_string_literal: true

module OptionsBuying
  module Strategies
    class VcpBreakout < BaseStrategy
      def check_entry(market_state)
        # Require ATR compression
        return nil unless OptionsBuying::ATRCompressionChecker.compressed?(@index_key)

        spot_ltp = market_state[:spot_ltp]
        inside_bar_range = find_inside_bar_range
        return nil unless inside_bar_range

        direction = determine_breakout_direction(spot_ltp, inside_bar_range)
        return nil unless direction

        # OI confirmation using ChainRadar max OI
        return nil unless oi_confirmed?(direction)

        radar = StateStore.radar_strikes(@index_key)
        option_type = direction == :bullish ? 'CE' : 'PE'
        target_strike = radar.find { |s| s[:type] == option_type }
        return nil unless target_strike

        metrics = {
          direction: direction,
          spot_ltp: spot_ltp,
          ib_high: inside_bar_range[:high],
          ib_low: inside_bar_range[:low]
        }

        sink_telemetry!(direction: direction, option_security_id: target_strike[:security_id], metrics: metrics)

        {
          direction: direction,
          option_security_id: target_strike[:security_id],
          metrics: metrics
        }
      end

      def name
        'vcp_breakout'
      end

      def required_regime
        :ranging
      end

      private

      def inside_bar_lookback
        (config[:inside_bar_lookback] || 5).to_i
      end

      def find_inside_bar_range
        candles = StateStore.index_candles(@index_key, '5')
        return nil if candles.blank? || candles.size < inside_bar_lookback

        # Check if the second to last candle is an inside bar
        mother_bar = candles[-3] # or we can scan the recent
        inside_bar = candles[-2]

        return nil unless mother_bar && inside_bar

        if inside_bar[:high].to_f < mother_bar[:high].to_f && inside_bar[:low].to_f > mother_bar[:low].to_f
          { high: inside_bar[:high].to_f, low: inside_bar[:low].to_f }
        end
      end

      def determine_breakout_direction(spot_ltp, range)
        return :bullish if spot_ltp > range[:high]
        return :bearish if spot_ltp < range[:low]
        nil
      end

      def oi_confirmed?(direction)
        # We want to see PE OI > CE OI below spot for bullish, and vice versa
        # Simply rely on resistance/support levels from radar
        if direction == :bullish
          support = StateStore.support(@index_key)
          support.present? && support < StateStore.cache_snapshot(index_sid)&.dig(:ltp).to_f
        else
          resistance = StateStore.resistance(@index_key)
          resistance.present? && resistance > StateStore.cache_snapshot(index_sid)&.dig(:ltp).to_f
        end
      end

      def index_sid
        IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }&.dig(:sid).to_s
      end
    end
  end
end
