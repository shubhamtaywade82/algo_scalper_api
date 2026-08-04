# frozen_string_literal: true

module OptionsBuying
  module Strategies
    # Primary options buying strategy using Multi-Timeframe (1m + 5m) Supertrend + ADX gating.
    # 1m is the execution/signal timeframe, 5m is the higher timeframe trend bias.
    class SupertrendAdx < BaseStrategy
      def check_entry(market_state)
        spot_ltp = market_state[:spot_ltp]

        instrument = Instrument.segment_index.find_by(symbol_name: @index_key)
        from = 6.hours.ago
        to = Time.current

        series_1m = Candles::Repository.series(instrument_key: @index_key, timeframe: '1m', from: from, to: to, include_forming: true, instrument: instrument)
        series_5m = Candles::Repository.series(instrument_key: @index_key, timeframe: '5m', from: from, to: to, include_forming: true, instrument: instrument)

        return nil unless series_1m&.candles&.any? && series_5m&.candles&.any?

        st_period = (config[:supertrend_period] || 10).to_i
        st_multiplier = (config[:supertrend_multiplier] || 2.0).to_f
        adx_min = (config[:adx_min] || config[:adx_threshold] || 20.0).to_f
        adx_period = (config[:adx_period] || 14).to_i

        # 1. 5m Higher Timeframe Bias
        res_5m = Indicators::Supertrend.new(series: series_5m, period: st_period, base_multiplier: st_multiplier).call
        return nil if res_5m[:trend].nil?

        trend_5m = res_5m[:trend]

        # 2. 1m Lower Timeframe Signal
        res_1m = Indicators::Supertrend.new(series: series_1m, period: st_period, base_multiplier: st_multiplier).call
        return nil if res_1m[:trend].nil?

        trend_1m = res_1m[:trend]

        # 3. Multi-Timeframe Alignment Check
        return nil unless trend_1m == trend_5m

        # 4. ADX Filter Gating on 1m
        adx = series_1m.adx(adx_period)
        return nil if adx.nil? || adx < adx_min

        direction = trend_1m == :bullish ? :bullish : :bearish

        radar = StateStore.radar_strikes(@index_key)
        option_type = direction == :bullish ? 'CE' : 'PE'
        target_strike = radar.find { |s| s[:type] == option_type }
        option_security_id = target_strike ? target_strike[:security_id] : @security_id

        metrics = {
          direction: direction,
          spot_ltp: spot_ltp,
          adx: adx.round(1),
          trend_1m: trend_1m,
          trend_5m: trend_5m
        }

        sink_telemetry!(direction: direction, option_security_id: option_security_id, metrics: metrics)

        {
          direction: direction,
          option_security_id: option_security_id,
          metrics: metrics
        }
      end

      def name
        'supertrend_adx'
      end

      def required_regime
        :all
      end
    end
  end
end
