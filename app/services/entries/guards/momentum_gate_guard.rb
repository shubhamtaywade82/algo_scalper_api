# frozen_string_literal: true

module Entries
  module Guards
    class MomentumGateGuard
      include BaseGuard

      DEFAULT_ADX_THRESHOLD = 25

      def self.call(context)
        return PASS unless enabled?

        index_key = (context[:index_cfg] || {})[:key].to_s.upcase
        return PASS if index_key.blank?

        instrument = context[:instrument]
        return PASS unless instrument

        series_15m = instrument.candle_series(interval: "15")
        return PASS unless series_15m&.candles&.size&.>= 20

        bb_pass = bb_breakout?(series_15m)
        adx_pass = adx_strong?(series_15m)

        return PASS if bb_pass
        return PASS if adx_pass

        { blocked: "No momentum: BB breakout=false, ADX=#{format_adx(series_15m)} (threshold: #{adx_threshold})" }
      rescue StandardError => e
        Rails.logger.warn("[MomentumGateGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :momentum_gate) || {}
        cfg.fetch(:enabled, false)
      end

      def self.bb_breakout?(series)
        detector = MarketRegimeDetector.new(series)
        detector.bollinger_band_breakout?
      end

      def self.adx_strong?(series)
        adx = series.adx(14)
        adx && adx.to_f >= adx_threshold
      end

      def self.adx_threshold
        cfg = AlgoConfig.fetch.dig(:risk, :momentum_gate) || {}
        (cfg[:adx_threshold] || DEFAULT_ADX_THRESHOLD).to_f
      end

      def self.format_adx(series)
        adx = series.adx(14)
        adx ? adx.round(1) : "N/A"
      rescue StandardError
        "N/A"
      end
    end
  end
end
