# frozen_string_literal: true

class LiveOptionSelector
  MIN_OPEN_INTEREST = 1_000
  MAX_SPREAD_PCT = 3.0

  def select(option_chain:, side:, moneyness:, spot_price:)
    rows = normalize_rows(option_chain)
    return nil if rows.empty?

    strike_step = detect_strike_step(rows)
    target_strike = target_strike_for(
      spot_price: spot_price.to_f,
      moneyness: moneyness,
      side: side,
      strike_step: strike_step
    )

    candidates = rows.filter_map do |row|
      leg = row[side]
      next unless tradable_leg?(leg)

      build_candidate(row: row, leg: leg, target_strike: target_strike)
    end

    candidates.min_by { |candidate| rank_key(candidate) }
  end

  private

  def normalize_rows(option_chain)
    option_chain.map do |strike, strike_data|
      {
        strike: strike.to_f,
        ce: normalize_leg(strike_data["ce"] || strike_data[:ce] || {}),
        pe: normalize_leg(strike_data["pe"] || strike_data[:pe] || {})
      }
    end
  end

  def normalize_leg(leg)
    {
      ltp: numeric(leg["last_price"] || leg[:last_price]),
      bid: numeric(leg["best_bid_price"] || leg[:best_bid_price]),
      ask: numeric(leg["best_ask_price"] || leg[:best_ask_price]),
      oi: numeric(leg["oi"] || leg[:oi]),
      volume: numeric(leg["volume"] || leg[:volume])
    }
  end

  def detect_strike_step(rows)
    strikes = rows.map { |row| row[:strike] }.uniq.sort
    diffs = strikes.each_cons(2).map { |left, right| right - left }.reject(&:zero?)
    return 50.0 if diffs.empty?

    diffs.min
  end

  def target_strike_for(spot_price:, moneyness:, side:, strike_step:)
    atm = round_to_step(spot_price, strike_step)
    return atm if moneyness == :atm

    offset = strike_step
    if moneyness == :itm
      side == :ce ? (atm - offset) : (atm + offset)
    else
      side == :ce ? (atm + offset) : (atm - offset)
    end
  end

  def tradable_leg?(leg)
    return false if leg[:ltp] <= 0.0
    return false if leg[:oi] < MIN_OPEN_INTEREST

    spread_pct = spread_percentage(leg[:bid], leg[:ask])
    !spread_pct.nil? && spread_pct <= MAX_SPREAD_PCT
  end

  def build_candidate(row:, leg:, target_strike:)
    {
      strike: row[:strike],
      ltp: leg[:ltp],
      bid: leg[:bid],
      ask: leg[:ask],
      oi: leg[:oi].to_i,
      volume: leg[:volume].to_i,
      spread_pct: spread_percentage(leg[:bid], leg[:ask]),
      strike_distance: (row[:strike] - target_strike).abs
    }
  end

  def rank_key(candidate)
    [candidate[:strike_distance], candidate[:spread_pct], -candidate[:oi], -candidate[:volume]]
  end

  def spread_percentage(bid, ask)
    return nil if bid <= 0.0 || ask <= 0.0

    mid = (bid + ask) / 2.0
    return nil if mid <= 0.0

    ((ask - bid) / mid) * 100.0
  end

  def round_to_step(value, step)
    (value / step).round * step
  end

  def numeric(value)
    value.to_f
  end
end
