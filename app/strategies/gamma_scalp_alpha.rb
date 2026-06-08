# frozen_string_literal: true

class GammaScalpAlpha < AlphaStrategy
  def scan
    return nil unless enabled?

    ltp = underlying_ltp
    return nil unless ltp

    bars = fetch_historical_bars(interval: 1, count: 60) # 1-hour of 1-min bars
    return nil if bars.size < 60

    rv = calculate_realized_volatility(bars)
    chain_data = instrument&.fetch_option_chain
    iv = extract_atm_iv(chain_data, atm_strike(ltp), :ce)

    return nil unless iv && rv > iv * 1.5 # Realized vol much higher than Implied

    direction = detect_micro_breakout(bars.last(5))
    return nil unless direction

    strike = atm_strike(ltp)
    sl_points = (ltp * 0.005).round(2) # Very tight 0.5% SL
    target_points = (sl_points * 2).round(2)

    build_signal(
      direction: direction,
      strike: strike,
      option_type: :atm,
      entry_price: ltp,
      stop_loss: direction == :ce ? ltp - sl_points : ltp + sl_points,
      target: direction == :ce ? ltp + target_points : ltp - target_points,
      trailing_jump: (sl_points * 0.3).round,
      confidence: 0.65,
      alpha_source: :gamma_scalp,
      iv_context: { realized_vol: rv, implied_vol: iv, ratio: (rv / iv).round(2) }
    )
  end

  private

  def calculate_realized_volatility(bars)
    returns = bars.each_cons(2).map do |prev, curr|
      Math.log((curr[:close] || curr['close']).to_f / (prev[:close] || prev['close']).to_f)
    end
    stdev = standard_deviation(returns)
    # Annualize: stdev * sqrt(minutes_in_year)
    # 375 mins per day * 252 days = 94500
    (stdev * Math.sqrt(94500) * 100).round(2)
  end

  def standard_deviation(array)
    return 0 if array.empty?
    m = array.sum / array.size.to_f
    sum = array.inject(0) { |accum, i| accum + (i - m)**2 }
    Math.sqrt(sum / array.size.to_f)
  end

  def extract_atm_iv(chain_data, strike, _direction)
    return nil unless chain_data && chain_data[:oc]
    leg = chain_data[:oc][strike.to_f.to_s]
    leg&.dig('ce', 'implied_volatility')&.to_f
  end

  def detect_micro_breakout(bars)
    closes = bars.map { |b| b[:close] || b['close'] || 0 }
    return nil if closes.size < 2

    prior_max = closes[0..-2].max
    prior_min = closes[0..-2].min

    if closes.last > prior_max
      :ce
    elsif closes.last < prior_min
      :pe
    end
  end
end
