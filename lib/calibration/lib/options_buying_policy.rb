# frozen_string_literal: true

class OptionsBuyingPolicy
  DEFAULT_CONFIG = {
    min_trend_adx: 18.0,
    strong_trend_adx: 35.0,
    moderate_trend_adx: 25.0,
    preferred_moneyness: {
      ce: :atm,
      pe: :atm
    }
  }.freeze

  def initialize(config: {})
    @config = deep_merge(DEFAULT_CONFIG, symbolize_hash(config))
  end

  def recommendation(signal:, adx:, atr_pct:)
    side = option_side_for(signal)
    return no_trade("latest signal is not a buy signal") if side.nil?
    return no_trade("adx below trend threshold") if adx.to_f < @config[:min_trend_adx].to_f

    {
      decision: :buy_option,
      side: side,
      moneyness: moneyness_for(side: side, adx: adx, atr_pct: atr_pct),
      notes: build_notes(adx: adx, atr_pct: atr_pct)
    }
  end

  private

  def option_side_for(signal)
    case signal
    when "BUY CALLS"
      :ce
    when "BUY PUTS"
      :pe
    end
  end

  def moneyness_for(side:, adx:, atr_pct:)
    return @config.dig(:preferred_moneyness, side) if adx.to_f >= @config[:strong_trend_adx].to_f && atr_pct.to_f >= 0.03
    return @config.dig(:preferred_moneyness, side) if adx.to_f >= @config[:moderate_trend_adx].to_f

    :atm
  end

  def build_notes(adx:, atr_pct:)
    ["ADX=#{adx}", "ATR%=#{atr_pct}"]
  end

  def no_trade(reason)
    { decision: :no_trade, reason: reason }
  end

  def symbolize_hash(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = symbolize_hash(v) }
    when Array
      value.map { |v| symbolize_hash(v) }
    when String
      %w[atm itm otm ce pe].include?(value.downcase) ? value.downcase.to_sym : value
    else
      value
    end
  end

  def deep_merge(base, overrides)
    base.merge(overrides) do |_key, left, right|
      left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
    end
  end
end
