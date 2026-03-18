# frozen_string_literal: true

module Market
  # Maps MarketRegimeDetector output to TradingContext symbols and a 0–100 score.
  class RegimeScorer
    REGIME_MAP = {
      "TRENDING_UP" => :trend_bull,
      "TRENDING_DOWN" => :trend_bear,
      "RANGING" => :chop,
      "CHOPPY" => :chop,
      "INSUFFICIENT_DATA" => :chop,
      "UNKNOWN" => :chop
    }.freeze

    def initialize(market:, indicators:)
      @market = market
      @indicators = indicators || {}
    end

    # @return [Hash] { regime: Symbol, score: Float (0–100) }
    def call
      regime_sym = resolve_regime
      score = resolve_score(regime_sym)

      { regime: regime_sym, score: score }
    end

    private

    def resolve_regime
      series = series_from_market
      return :chop unless series && series.candles.size >= 20

      detector = MarketRegimeDetector.new(series)
      result = detector.detect
      raw = result[:regime].to_s.upcase
      REGIME_MAP[raw] || :chop
    end

    def resolve_score(regime_sym)
      adx = @indicators[:adx_value]
      confidence = @indicators[:regime_confidence]

      base = (adx.is_a?(Numeric) ? adx : confidence).to_f
      base = 50.0 if base.zero? && regime_sym == :chop

      [[100.0, base].min, 0.0].max.round(2)
    end

    def series_from_market
      return @market if @market.respond_to?(:candles)
      return @market if @market.respond_to?(:series) && @market.series.respond_to?(:candles)

      nil
    end
  end
end
