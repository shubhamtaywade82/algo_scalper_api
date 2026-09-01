# frozen_string_literal: true

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

# Supertrend + VWAP confluence, per the doc's Strategy 3 community setup: buy CE only when
# Supertrend is bullish AND price is above VWAP (PE is the symmetric mirror). The doc is
# explicit that this setup has "no credible quantified options-buying backtest" and should be
# treated as a trend filter, not a standalone edge — included here per the doc's full strategy
# list, with that caveat carried into the strategy's own reasoning tag. Stop is the Supertrend
# line value at entry (frozen, not recomputed bar-by-bar); target is the prior swing extreme,
# extended to meet a minimum 1.5:1 if the raw swing distance falls short.
class SupertrendVwapStrategy < BaseStrategy
  def call(context)
    series = context.candles.call('5m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    st_period = (params[:supertrend_period] || 10).to_i
    st_multiplier = (params[:supertrend_multiplier] || 3.0).to_f
    min_rr = (params[:min_reward_risk] || 1.5).to_f
    strike_pref = (params[:strike_pref] || 'ATM').to_s

    result = Indicators::Supertrend.new(series: series, period: st_period, base_multiplier: st_multiplier).call
    last_idx = result[:line]&.rindex { |v| !v.nil? }
    return Signals::Hold.new(reason: 'supertrend_unavailable') unless last_idx

    vwap = series.current_vwap
    return Signals::Hold.new(reason: 'vwap_unavailable') if vwap.nil? || vwap.zero?

    close = series.candles[last_idx].close
    line_value = result[:line][last_idx]

    if result[:trend] == :bullish && close > line_value && close > vwap
      stop = line_value
      risk = close - stop
      return Signals::Hold.new(reason: 'invalid_risk') if risk <= 0

      target = [series.previous_swing_high, close + (min_rr * risk)].compact.max
      Signals::BuyCall.new(
        confidence: 0.6,
        reason: "supertrend_vwap_bullish(unvalidated) st=#{line_value.round(1)} vwap=#{vwap.round(1)}",
        metadata: { strike_pref: strike_pref, exit_rules: { stop_index_level: stop, target_index_level: target, giveback_enabled: false } }
      )
    elsif result[:trend] == :bearish && close < line_value && close < vwap
      stop = line_value
      risk = stop - close
      return Signals::Hold.new(reason: 'invalid_risk') if risk <= 0

      target = [series.previous_swing_low, close - (min_rr * risk)].compact.min
      Signals::BuyPut.new(
        confidence: 0.6,
        reason: "supertrend_vwap_bearish(unvalidated) st=#{line_value.round(1)} vwap=#{vwap.round(1)}",
        metadata: { strike_pref: strike_pref, exit_rules: { stop_index_level: stop, target_index_level: target, giveback_enabled: false } }
      )
    else
      Signals::Hold.new(reason: 'trend_vwap_not_aligned')
    end
  end
end
