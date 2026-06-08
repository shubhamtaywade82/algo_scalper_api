# frozen_string_literal: true

class VolExpansionAlpha < AlphaStrategy
  IV_PERCENTILE_THRESHOLD = 20

  def scan
    return nil unless enabled?

    ltp = underlying_ltp
    return nil unless ltp

    iv_history = IvSnapshot.historical_iv(index_key: @index_key, days: 90)
    # Cold start check: if we don't have enough IV data, we can't reliably calculate percentile
    return nil if iv_history.size < 30

    chain_data = instrument&.fetch_option_chain
    iv_current = extract_atm_iv(chain_data, atm_strike(ltp), :ce) # Use CE as proxy

    return nil unless iv_current

    iv_pct = iv_percentile(current_iv: iv_current, history: iv_history)
    return nil unless iv_pct < IV_PERCENTILE_THRESHOLD

    # Additional filter: ensure market isn't in extreme chop
    bars = fetch_historical_bars(interval: 5, count: 5)
    recent_bias = detect_recent_bias(bars)

    sl_points = (ltp * 0.015).round(2) # 1.5% SL on index
    target_points = (ltp * 0.03).round(2) # 3% Target

    build_signal(
      direction: recent_bias,
      strike: atm_strike(ltp),
      option_type: :atm,
      entry_price: ltp,
      stop_loss: recent_bias == :ce ? ltp - sl_points : ltp + sl_points,
      target: recent_bias == :ce ? ltp + target_points : ltp - target_points,
      trailing_jump: 0,
      confidence: 0.55 + (0.25 * (1 - iv_pct / 100)), # Higher confidence when IV is extremely low
      alpha_source: :vol_expansion,
      iv_context: { percentile: iv_pct, current: iv_current, mean: (iv_history.sum / iv_history.size).round(2) }
    )
  end

  private

  def extract_atm_iv(chain_data, strike, _direction)
    return nil unless chain_data && chain_data[:oc]
    leg = chain_data[:oc][strike.to_f.to_s]
    leg&.dig('ce', 'implied_volatility')&.to_f
  end

  def detect_recent_bias(bars)
    return :ce if bars.empty?
    closes = bars.map { |b| b[:close] || b['close'] || 0 }
    closes.last > closes.first ? :ce : :pe
  end
end
