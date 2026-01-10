# app/strategies/supertrend_adx_strategy.rb
# frozen_string_literal: true

# Supertrend + ADX Strategy (backward compatible)
# Now uses modular indicator system internally
class SupertrendAdxStrategy
  attr_reader :series, :supertrend_cfg, :adx_min_strength

  def initialize(series:, supertrend_cfg:, adx_min_strength: 20)
    @series = series
    @supertrend_cfg = supertrend_cfg
    @adx_min_strength = adx_min_strength

    # Use modular indicator system internally
    @multi_indicator_strategy = MultiIndicatorStrategy.new(
      series: series,
      indicators: [
        { type: 'supertrend', config: { supertrend_cfg: supertrend_cfg, trading_hours_filter: true } },
        { type: 'adx', config: { min_strength: adx_min_strength, period: 14, trading_hours_filter: true } }
      ],
      confirmation_mode: :all,
      min_confidence: 60
    )
  end

  # Generates entry signal at given candle index
  # Returns: { type: :ce/:pe, confidence: 0-100 } or nil
  delegate :generate_signal, to: :@multi_indicator_strategy
end
