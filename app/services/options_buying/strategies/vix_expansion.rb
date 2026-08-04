# frozen_string_literal: true

module OptionsBuying
  module Strategies
    class VixExpansion < BaseStrategy
      def check_entry(market_state)
        # 1. Require low VIX regime
        vix_filter = OptionsBuying::VixFilter.new
        percentile = vix_filter.current_percentile
        return nil unless percentile && percentile < 20.0

        # 2. VIX rises > 5% intraday
        vix = vix_filter.current_vix
        vix_open = Live::TickCache.open_price('IDX_I', '26009') # INDIA VIX sid
        return nil unless vix && vix_open&.positive?

        rise_pct = (vix - vix_open) / vix_open
        return nil unless rise_pct > 0.05

        # 3. Direction via ADX
        direction = determine_direction
        return nil unless direction

        # Select option
        radar = StateStore.radar_strikes(@index_key)
        option_type = direction == :bullish ? 'CE' : 'PE'
        target_strike = radar.find { |s| s[:type] == option_type }
        return nil unless target_strike

        metrics = {
          direction: direction,
          vix_percentile: percentile,
          vix_rise_pct: rise_pct
        }

        sink_telemetry!(direction: direction, option_security_id: target_strike[:security_id], metrics: metrics)

        {
          direction: direction,
          option_security_id: target_strike[:security_id],
          metrics: metrics
        }
      end

      def name
        'vix_expansion'
      end

      def required_regime
        :low_vix
      end

      private

      def determine_direction
        # Use MarketRegimeDetector to get current trend/direction if possible.
        # Alternatively, calculate 14-period ADX manually here.
        # Let's rely on MarketRegimeDetector for ADX stats.
        index_sid = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }&.dig(:sid).to_s
        return nil unless index_sid

        regime_data = ::MarketRegimeDetector.new(index_sid).detect
        return :bullish if regime_data[:regime] == 'TRENDING_UP'
        return :bearish if regime_data[:regime] == 'TRENDING_DOWN'
        nil
      end
    end
  end
end
