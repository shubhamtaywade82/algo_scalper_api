# frozen_string_literal: true

module OptionsBuying
  # Service to calculate ATR and check setup compression ratio for options buying setup.
  class ATRCompressionChecker
    DEFAULT_MAX_SETUP_RATIO = 0.30
    DEFAULT_ATR_PERIOD = 14

    def self.compressed?(instrument)
      new(instrument).compressed?
    end

    def self.setup_ratio(instrument)
      new(instrument).setup_ratio
    end

    def self.compute_daily_atr_for(instrument)
      new(instrument).compute_daily_atr
    end

    def initialize(instrument)
      @instrument = instrument
    end

    def compressed?
      return false unless Mode.compression_enabled?

      ratio = setup_ratio
      return false unless ratio

      ratio < max_setup_ratio
    rescue StandardError => e
      Rails.logger.warn("[ATRCompressionChecker] #{e.class} - #{e.message}")
      false
    end

    def setup_ratio
      atr = daily_atr_baseline
      range = today_session_range
      return nil unless atr&.positive? && range&.positive?

      range / atr
    end

    def daily_atr_baseline
      index_key = index_key_for_instrument
      cached = StateStore.daily_atr(index_key) if index_key
      return cached if cached&.positive?

      compute_daily_atr
    end

    def compute_daily_atr
      to_date = Market::Calendar.trading_days_ago(1).to_s
      from_date = Market::Calendar.trading_days_ago(40).to_s
      raw = @instrument.historical_ohlc(from_date: from_date, to_date: to_date)
      return nil if raw.blank?

      series = CandleSeries.new(symbol: @instrument.symbol_name, interval: '1D')
      series.load_from_raw(raw)
      series.atr(atr_period)
    end

    private

    def config
      Mode.config[:atr_compression] || {}
    end

    def max_setup_ratio
      (config[:max_setup_ratio] || DEFAULT_MAX_SETUP_RATIO).to_f
    end

    def atr_period
      (config[:atr_period] || DEFAULT_ATR_PERIOD).to_i
    end

    def today_session_range
      series = @instrument.candle_series(interval: '5')
      return nil unless series&.candles&.any?

      today = Time.zone.today
      today_candles = series.candles.select { |c| c.timestamp.to_date == today }
      return nil if today_candles.empty?

      today_candles.map(&:high).max - today_candles.map(&:low).min
    end

    def index_key_for_instrument
      sid = @instrument.security_id.to_s
      IndexConfigLoader.load_indices.find { |idx| idx[:sid].to_s == sid }&.dig(:key)
    rescue StandardError
      nil
    end
  end
end
