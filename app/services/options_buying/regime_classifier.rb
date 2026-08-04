# frozen_string_literal: true

module OptionsBuying
  # Regime classifier extending MarketRegimeDetector specifically for Options Buying
  class RegimeClassifier
    def self.detect(index_key)
      new(index_key).detect
    end

    def initialize(index_key)
      @index_key = index_key.to_s.upcase
    end

    def detect
      return :event_day if event_day?
      return :late_day if late_day?
      return :low_vix if low_vix_regime?

      base_regime = detect_base_regime
      if %w[TRENDING_UP TRENDING_DOWN].include?(base_regime)
        :trending
      else
        :ranging
      end
    end

    private

    def detect_base_regime
      index_config = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }
      return 'RANGING' unless index_config

      instrument = IndexInstrumentCache.instance.get_or_fetch(index_config)
      return 'RANGING' unless instrument

      series = instrument.candle_series(interval: '5')
      return 'RANGING' unless series&.candles&.any?

      result = ::MarketRegimeDetector.new(series).detect
      result[:regime]
    rescue StandardError => e
      Rails.logger.warn("[RegimeClassifier] failed to detect base regime: #{e.message}")
      'RANGING'
    end

    def event_day?
      events = Mode.config[:event_calendar] || []
      today_iso = Time.zone.today.iso8601
      events.include?(today_iso)
    end

    def late_day?
      Time.current.strftime('%H:%M') >= '13:45'
    end

    def low_vix_regime?
      vix_tracker = OptionsBuying::VixFilter.new
      percentile = vix_tracker.current_percentile
      percentile.present? && percentile < 30.0
    end
  end
end
