# frozen_string_literal: true

module CandleExtension
  extend ActiveSupport::Concern

  included do
    def candles(interval: "5")
      @ohlc_cache ||= {}
      @last_ohlc_fetched ||= {}

      cached = @ohlc_cache[interval]
      return cached if cached.present? && !ohlc_stale?(interval)

      raw_data = intraday_ohlc(interval: interval)
      if raw_data.blank?
        Rails.logger.warn(
          "No OHLC data returned for #{self.class.name} #{security_id} (interval=#{interval})."
        ) if defined?(Rails)
        return cached
      end

      series = CandleSeries.new(symbol: symbol_name, interval: interval)
      series.load_from_raw(raw_data)

      @last_ohlc_fetched[interval] = Time.current
      @ohlc_cache[interval] = series
    rescue StandardError => e
      Rails.logger.error(
        "Failed to fetch candles for #{self.class.name} #{security_id}: #{e.message}"
      ) if defined?(Rails)
      cached
    end

    def candle_series(interval: "5")
      candles(interval: interval)
    end

    def rsi(period = 14, interval: "5")
      cs = candle_series(interval: interval)
      cs&.rsi(period)
    end

    def macd(fast_period = 12, slow_period = 26, signal_period = 9, interval: "5")
      cs = candle_series(interval: interval)
      macd_result = cs&.macd(fast_period, slow_period, signal_period)
      return nil unless macd_result

      {
        macd: macd_result[0],
        signal: macd_result[1],
        histogram: macd_result[2]
      }
    end

    def adx(period = 14, interval: "5")
      cs = candle_series(interval: interval)
      return nil unless cs

      ta_adx = TechnicalAnalysis::Adx.calculate(cs.hlc, period: period).first
      ta_adx&.adx
    rescue NameError
      nil
    end

    def supertrend_signal(interval: "5")
      cs = candle_series(interval: interval)
      cs&.supertrend_signal
    end

    def liquidity_grab_up?(interval: "5")
      cs = candle_series(interval: interval)
      cs&.liquidity_grab_up?
    end

    def liquidity_grab_down?(interval: "5")
      cs = candle_series(interval: interval)
      cs&.liquidity_grab_down?
    end

    def bollinger_bands(period: 20, interval: "5")
      cs = candle_series(interval: interval)
      cs&.bollinger_bands(period: period)
    end

    def donchian_channel(period: 20, interval: "5")
      cs = candle_series(interval: interval)
      cs&.donchian_channel(period: period)
    end

    def obv(interval: "5")
      cs = candle_series(interval: interval)
      cs&.on_balance_volume
    end

    private

    def ohlc_stale?(interval)
      @last_ohlc_fetched ||= {}
      last = @last_ohlc_fetched[interval]
      return true unless last

      Time.current - last > 5.minutes
    end
  end
end
