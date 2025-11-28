# frozen_string_literal: true

module Risk
  # Service to detect current volatility regime based on VIX levels
  # Regimes: :high (VIX > 20), :medium (VIX 15-20), :low (VIX < 15)
  class VolatilityRegimeService < ApplicationService
    VIX_SYMBOL = 'INDIAVIX'
    DEFAULT_REGIME = :medium

    attr_reader :vix_value, :regime

    def initialize(vix_value: nil)
      @vix_value = vix_value
      @regime = nil
    end

    def call
      vix = fetch_vix_value
      @vix_value = vix
      @regime = determine_regime(vix)
      {
        regime: @regime,
        vix_value: @vix_value,
        regime_name: regime_name(@regime)
      }
    rescue StandardError => e
      Rails.logger.error("[VolatilityRegimeService] Error: #{e.class} - #{e.message}")
      {
        regime: DEFAULT_REGIME,
        vix_value: nil,
        regime_name: regime_name(DEFAULT_REGIME)
      }
    end

    private

    def fetch_vix_value
      return @vix_value.to_f if @vix_value&.positive?

      # Try to fetch VIX from instrument
      vix_instrument = find_vix_instrument
      return fetch_vix_from_instrument(vix_instrument) if vix_instrument

      # Fallback: Use ATR-based volatility proxy if VIX not available
      Rails.logger.warn('[VolatilityRegimeService] VIX instrument not found, using ATR proxy')
      calculate_atr_proxy
    end

    def find_vix_instrument
      # Try multiple possible VIX symbol names
      symbols = [VIX_SYMBOL, 'VIX', 'INDIA VIX', 'NIFTY VIX']
      symbols.each do |symbol|
        instrument = Instrument.find_by(symbol_name: symbol)
        return instrument if instrument
      end
      nil
    rescue StandardError => e
      Rails.logger.debug { "[VolatilityRegimeService] Instrument lookup failed: #{e.message}" }
      nil
    end

    def fetch_vix_from_instrument(instrument)
      # Try tick cache first
      ltp = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id.to_s)
      return ltp.to_f if ltp&.positive?

      # Try Redis tick cache
      tick = Live::RedisTickCache.instance.fetch_tick(instrument.exchange_segment,
                                                      instrument.security_id.to_s)
      return tick&.dig(:ltp)&.to_f if tick&.dig(:ltp)&.positive?

      # Fallback to API
      api_ltp = instrument.ltp
      return api_ltp.to_f if api_ltp&.positive?

      nil
    rescue StandardError => e
      Rails.logger.debug { "[VolatilityRegimeService] VIX fetch failed: #{e.message}" }
      nil
    end

    def calculate_atr_proxy
      # Use Nifty ATR as volatility proxy if VIX unavailable
      # This is a fallback method - not as accurate as VIX but better than nothing
      nifty = Instrument.find_by(symbol_name: 'NIFTY')
      return nil unless nifty

      series = nifty.candle_series(interval: '5')
      return nil unless series&.candles&.any?

      calculator = Indicators::Calculator.new(series)
      atr = calculator.atr(14)
      return nil unless atr&.positive?

      # Convert ATR to approximate VIX-like value
      # Rough approximation: ATR% * 100 gives approximate volatility percentage
      closes = series.closes
      return nil unless closes&.any?

      current_price = closes.last.to_f
      return nil unless current_price.positive?

      atr_pct = (atr / current_price) * 100
      # Scale to approximate VIX range (typically 10-30)
      (atr_pct * 2.0).clamp(10.0, 35.0)
    rescue StandardError => e
      Rails.logger.debug { "[VolatilityRegimeService] ATR proxy failed: #{e.message}" }
      nil
    end

    def determine_regime(vix_value)
      return DEFAULT_REGIME unless vix_value&.positive?

      config = fetch_config
      high_threshold = config[:high] || 20.0
      medium_threshold = config[:medium] || 15.0

      if vix_value > high_threshold
        :high
      elsif vix_value >= medium_threshold
        :medium
      else
        :low
      end
    end

    def fetch_config
      AlgoConfig.fetch.dig(:risk, :volatility_regimes, :vix_thresholds) || {}
    rescue StandardError
      { high: 20.0, medium: 15.0 }
    end

    def regime_name(regime)
      case regime
      when :high then 'High Volatility'
      when :medium then 'Medium Volatility'
      when :low then 'Low Volatility'
      else 'Unknown'
      end
    end
  end
end
