# frozen_string_literal: true

module OptionsBuying
  module Strategies
    class IvPercentileConfluence < BaseStrategy
      def check_entry(market_state)
        # 1. IV Percentile check
        iv_rank = current_iv_rank
        return nil unless iv_rank && iv_rank < 30.0
        return nil if iv_rank > 70.0 # Strict reject

        spot_ltp = market_state[:spot_ltp]

        # 2. Break 20EMA on 15-min with volume
        direction = evaluate_ema_breakout(spot_ltp)
        return nil unless direction

        # 3. OI Confirmation
        return nil unless oi_confirmed?(direction)

        # Select option
        radar = StateStore.radar_strikes(@index_key)
        option_type = direction == :bullish ? 'CE' : 'PE'
        target_strike = radar.find { |s| s[:type] == option_type }
        return nil unless target_strike

        metrics = {
          direction: direction,
          spot_ltp: spot_ltp,
          iv_rank: iv_rank
        }

        sink_telemetry!(direction: direction, option_security_id: target_strike[:security_id], metrics: metrics)

        {
          direction: direction,
          option_security_id: target_strike[:security_id],
          metrics: metrics
        }
      end

      def name
        'iv_percentile_confluence'
      end

      def required_regime
        :low_vix
      end

      private

      def current_iv_rank
        # Fetch current IV rank from IvRankTracker
        # IvRankTracker records per index.
        # Ensure we have the latest IV to check.
        analyzer = Options::DerivativeChainAnalyzer.new(index_key: @index_key)
        spot = analyzer.spot_ltp
        return nil unless spot

        atm_strike = analyzer.select_candidates(limit: 2, direction: :bullish).first
        return nil unless atm_strike

        iv = atm_strike[:iv]&.to_f
        return nil unless iv&.positive?

        # This calculates percentile_rank on the fly based on history
        Options::IvRankTracker.instance.percentile_rank(index_key: @index_key, iv: iv)
      end

      def evaluate_ema_breakout(spot_ltp)
        candles = StateStore.index_candles(@index_key, '15')
        return nil if candles.blank? || candles.size < 20

        closes = candles.map { |c| c[:close].to_f }
        ema20 = calculate_ema(closes, 20)
        prev_close = closes[-2]

        current_vol = candles.last[:volume].to_f
        avg_vol = candles.last(10).sum { |c| c[:volume].to_f } / 10.0

        return nil unless current_vol > (avg_vol * 1.5)

        if prev_close < ema20 && spot_ltp > ema20
          :bullish
        elsif prev_close > ema20 && spot_ltp < ema20
          :bearish
        end
      end

      def calculate_sma(prices, period)
        prices.last(period).sum / period.to_f
      end

      def calculate_ema(prices, period)
        multiplier = 2.0 / (period + 1)
        ema = calculate_sma(prices.first(period), period)
        prices[period..].each do |price|
          ema = ((price - ema) * multiplier) + ema
        end
        ema
      end

      def oi_confirmed?(direction)
        # Check against basic radar support/resistance
        index_sid = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }&.dig(:sid).to_s
        spot_ltp = StateStore.cache_snapshot(index_sid)&.dig(:ltp).to_f

        if direction == :bullish
          support = StateStore.support(@index_key)
          support.present? && support < spot_ltp
        else
          resistance = StateStore.resistance(@index_key)
          resistance.present? && resistance > spot_ltp
        end
      end
    end
  end
end
