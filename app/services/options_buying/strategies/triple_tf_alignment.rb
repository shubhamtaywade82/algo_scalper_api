# frozen_string_literal: true

module OptionsBuying
  module Strategies
    class TripleTfAlignment < BaseStrategy
      def check_entry(market_state)
        spot_ltp = market_state[:spot_ltp]

        # 1. Daily trend
        daily_trend = determine_daily_trend
        return nil unless daily_trend

        # 2. Hourly trend
        hourly_trend = determine_hourly_trend
        return nil unless hourly_trend == daily_trend

        # 3. 15m pullback setup
        setup_direction = evaluate_pullback_setup(spot_ltp, daily_trend)
        return nil unless setup_direction == daily_trend

        radar = StateStore.radar_strikes(@index_key)
        option_type = setup_direction == :bullish ? 'CE' : 'PE'
        # Target 1-2 strikes ITM, Radar gives us ATM mostly, so let's select nearest ATM from radar for now
        target_strike = radar.find { |s| s[:type] == option_type }
        return nil unless target_strike

        metrics = {
          direction: setup_direction,
          spot_ltp: spot_ltp,
          trend: daily_trend
        }

        sink_telemetry!(direction: setup_direction, option_security_id: target_strike[:security_id], metrics: metrics)

        {
          direction: setup_direction,
          option_security_id: target_strike[:security_id],
          metrics: metrics
        }
      end

      def name
        'triple_tf_alignment'
      end

      def required_regime
        :trending
      end

      private

      def daily_ma_period
        (config[:daily_ma_period] || 50).to_i
      end

      def hourly_ema_period
        (config[:hourly_ema_period] || 20).to_i
      end

      def determine_daily_trend
        candles = Market::CandleSeries.new(
          security_id: index_sid, segment: 'IDX_I', timeframe: 'D'
        ).fetch(limit: daily_ma_period + 20)
        return nil if candles.size < daily_ma_period

        closes = candles.map { |c| c[:close].to_f }
        ma50 = calculate_sma(closes, 50)
        ema20 = calculate_ema(closes, 20)
        ema50 = calculate_ema(closes, 50)

        current_close = closes.last
        if current_close > ma50 && ema20 > ema50
          :bullish
        elsif current_close < ma50 && ema20 < ema50
          :bearish
        end
      end

      def determine_hourly_trend
        candles = Market::CandleSeries.new(
          security_id: index_sid, segment: 'IDX_I', timeframe: '60'
        ).fetch(limit: hourly_ema_period * 2)
        return nil if candles.size < hourly_ema_period

        closes = candles.map { |c| c[:close].to_f }
        ema20 = calculate_ema(closes, 20)
        prev_ema20 = calculate_ema(closes[0...-1], 20)
        current_close = closes.last

        if current_close > ema20 && ema20 > prev_ema20
          :bullish
        elsif current_close < ema20 && ema20 < prev_ema20
          :bearish
        end
      end

      def evaluate_pullback_setup(spot_ltp, trend)
        # Pullback to 20EMA or VWAP on 15m
        candles = Market::CandleSeries.new(
          security_id: index_sid, segment: 'IDX_I', timeframe: '15'
        ).fetch(limit: 50)
        return nil if candles.size < 20

        closes = candles.map { |c| c[:close].to_f }
        ema20 = calculate_ema(closes, 20)

        vwap = OptionsBuying::VwapCalculator.new(@index_key).compute(index_sid)

        near_ema = (spot_ltp - ema20).abs / spot_ltp < 0.002
        near_vwap = vwap && (spot_ltp - vwap).abs / spot_ltp < 0.002

        return nil unless near_ema || near_vwap

        # RSI confirmation
        rsi = calculate_rsi(closes, 14)
        rsi_range = config[:pullback_rsi_range] || [40, 60]
        return nil unless rsi.between?(rsi_range[0], rsi_range[1])

        trend
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

      def calculate_rsi(prices, period)
        gains = []
        losses = []

        prices.each_cons(2) do |prev, curr|
          change = curr - prev
          if change.positive?
            gains << change
            losses << 0
          else
            gains << 0
            losses << change.abs
          end
        end

        avg_gain = gains.last(period).sum / period.to_f
        avg_loss = losses.last(period).sum / period.to_f

        return 100 if avg_loss.zero?

        rs = avg_gain / avg_loss
        100.0 - (100.0 / (1.0 + rs))
      end

      def index_sid
        IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }&.dig(:sid).to_s
      end
    end
  end
end
