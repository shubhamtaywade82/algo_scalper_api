# frozen_string_literal: true

module Entries
  module Guards
    class RegimeGuard
      include BaseGuard

      DEFAULT_ADX_THRESHOLD = 25
      DEFAULT_BLOCK_REGIMES = %w[CHOPPY].freeze

      def self.call(context)
        cfg = config
        return PASS unless cfg.fetch(:enabled, false)

        index_key = (context[:index_cfg] || {})[:key].to_s.upcase
        return PASS if index_key.blank?

        instrument = context[:instrument]
        return PASS unless instrument

        series_15m = instrument.candle_series(interval: "15")
        return PASS unless series_15m&.candles&.size&.>= 20

        regime_data = detect_regime(series_15m)
        return PASS unless regime_data

        regime = regime_data[:regime].to_s.upcase
        block_regimes = cfg[:block_regimes] || DEFAULT_BLOCK_REGIMES
        return PASS unless block_regimes.include?(regime)

        adx = series_15m.adx(14).to_f
        bypass_adx = (cfg[:bypass_adx] || DEFAULT_ADX_THRESHOLD).to_f
        return PASS if adx >= bypass_adx

        { blocked: "Regime #{regime} (ADX=#{adx.round(1)} < #{bypass_adx}) blocks entry" }
      rescue StandardError => e
        Rails.logger.warn("[RegimeGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.config
        AlgoConfig.fetch.dig(:risk, :regime_guard) || {}
      rescue StandardError
        {}
      end

      def self.detect_regime(series)
        MarketRegimeDetector.new(series).detect
      rescue StandardError
        nil
      end
    end
  end
end
