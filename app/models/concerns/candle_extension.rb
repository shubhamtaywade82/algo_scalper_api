# frozen_string_literal: true

module CandleExtension
  extend ActiveSupport::Concern

  included do
    def candles(interval: '5')
      @ohlc_cache ||= {}

      # Check if caching is disabled for fresh data
      freshness_config = AlgoConfig.fetch[:data_freshness] || {}
      disable_caching = freshness_config[:disable_ohlc_caching] || false

      if disable_caching
        Rails.logger.debug { "[CandleExtension] Fresh data mode - bypassing cache for #{symbol_name}" }
        return fetch_fresh_candles(interval)
      end

      cached_series = @ohlc_cache[interval]
      return cached_series if cached_series && !ohlc_stale?(interval)

      fetch_fresh_candles(interval)
    end

    def fetch_fresh_candles(interval)
      raw_data = intraday_ohlc(interval: interval)
      return nil if raw_data.blank?

      @ohlc_cache[interval] = CandleSeries.new(symbol: symbol_name, interval: interval).tap do |series|
        series.load_from_raw(raw_data)
      end
    end

    def ohlc_stale?(interval)
      @last_ohlc_fetched ||= {}

      # Use configured cache duration or default
      freshness_config = AlgoConfig.fetch[:data_freshness] || {}
      cache_duration_minutes = freshness_config[:ohlc_cache_duration_minutes] || 5

      return true unless @last_ohlc_fetched[interval]

      Time.current - @last_ohlc_fetched[interval] > cache_duration_minutes.minutes
    ensure
      @last_ohlc_fetched[interval] = Time.current
    end

    def candle_series(interval: '5')
      candles(interval: interval)
    end

    def rsi(period = 14, interval: '5')
      cs = candles(interval: interval)
      cs&.rsi(period)
    end

    def macd(fast_period = 12, slow_period = 26, signal_period = 9, interval: '5')
      cs = candles(interval: interval)
      macd_result = cs&.macd(fast_period, slow_period, signal_period)
      return nil unless macd_result

      {
        macd: macd_result[0],
        signal: macd_result[1],
        histogram: macd_result[2]
      }
    end

    def adx(period = 14, interval: '5')
      cs = candles(interval: interval)
      closes = cs&.closes
      highs  = cs&.highs
      lows   = cs&.lows
      return nil unless closes && highs && lows

      hlc = cs.candles.each_with_index.map do |c, _i|
        {
          date_time: Time.zone.at(c.timestamp || 0),
          high: c.high,
          low: c.low,
          close: c.close
        }
      end

      ta_adx = TechnicalAnalysis::Adx.calculate(hlc, period: period).first
      ta_adx&.adx
    end

    def supertrend_signal(interval: '5')
      cs = candles(interval: interval)
      cs&.supertrend_signal
    end

    def liquidity_grab_up?(interval: '5')
      cs = candles(interval: interval)
      cs&.liquidity_grab_up?
    end

    def liquidity_grab_down?(interval: '5')
      cs = candles(interval: interval)
      cs&.liquidity_grab_down?
    end

    def bollinger_bands(period: 20, interval: '5')
      cs = candles(interval: interval)
      return nil unless cs

      cs.bollinger_bands(period: period)
    end

    def donchian_channel(period: 20, interval: '5')
      cs = candles(interval: interval)
      return nil unless cs

      dc = cs.candles.each_with_index.map do |c, _i|
        {
          date_time: Time.zone.at(c.timestamp || 0),
          value: c.close
        }
      end
      TechnicalAnalysis::Dc.calculate(dc, period: period)
    end

    def obv(interval: '5')
      series = candles(interval: interval)
      return nil unless series

      dcv = series.candles.each_with_index.map do |c, _i|
        {
          date_time: Time.zone.at(c.timestamp || 0),
          close: c.close,
          volume: c.volume || 0
        }
      end

      TechnicalAnalysis::Obv.calculate(dcv)
    end
  end
end
