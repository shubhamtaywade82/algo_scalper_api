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
        # Rails.logger.debug { "[CandleExtension] Fresh data mode - bypassing cache for #{symbol_name}" }
        return fetch_fresh_candles(interval)
      end

      cached_series = @ohlc_cache[interval]
      return cached_series if cached_series && !ohlc_stale?(interval)

      fetch_fresh_candles(interval)
    end

    def fetch_fresh_candles(interval)
      # For live trading, include today's data to get the most recent completed candles
      # Check if we're in live mode (not backtest/script mode)
      include_today = !Rails.env.test? &&
                      ENV['BACKTEST_MODE'] != '1' &&
                      ENV['SCRIPT_MODE'] != '1' &&
                      !($PROGRAM_NAME.include?('runner') if defined?($PROGRAM_NAME))

      if include_today
        # Include today's date to get the most recent candles
        # Use trading days, not calendar days, to avoid weekends/holidays
        to_date = if defined?(Market::Calendar) && Market::Calendar.respond_to?(:today_or_last_trading_day)
                    Market::Calendar.today_or_last_trading_day.to_s
                  elsif defined?(MarketCalendar) && MarketCalendar.respond_to?(:today_or_last_trading_day)
                    MarketCalendar.today_or_last_trading_day.to_s
                  else
                    Time.zone.today.to_s
                  end

        # Get from_date as 2 trading days ago (not 2 calendar days)
        from_date = if defined?(Market::Calendar) && Market::Calendar.respond_to?(:trading_days_ago)
                      Market::Calendar.trading_days_ago(2).to_s
                    elsif defined?(MarketCalendar) && MarketCalendar.respond_to?(:trading_days_ago)
                      MarketCalendar.trading_days_ago(2).to_s
                    else
                      (Date.parse(to_date) - 2).to_s # Fallback to calendar days
                    end

        Rails.logger.debug { "[CandleExtension] Fetching OHLC for #{symbol_name} @ #{interval}m: from_date=#{from_date}, to_date=#{to_date} (including today, using trading days)" }
        raw_data = intraday_ohlc(interval: interval, from_date: from_date, to_date: to_date, days: 2)
      else
        # For backtest/script mode, use default (excludes today)
        raw_data = intraday_ohlc(interval: interval)
      end

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
      cs&.adx(period)
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
    rescue NoMethodError => e
      raise e
    rescue StandardError => e
      # OBV.calculate might have different signature - try alternative approach
      Rails.logger.warn("[CandleExtension] OBV calculation failed: #{e.message}")
      nil
    end
  end
end
