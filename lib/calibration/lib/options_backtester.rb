# frozen_string_literal: true

require "time"
require "date"
require "csv"
require "json"
require_relative "options_buying_policy"

class OptionsBacktester
  DEFAULT_CONFIG = {
    expiry_flag: "WEEK",
    expiry_code: 1,
    options_exchange_segment: "NSE_FNO",
    risk: {
      sl_pct: 0.30,
      tp_pct: 0.60,
      max_hold_bars: 20
    },
    liquidity: {
      min_oi: 1_000,
      # ExpiredOptionsData has no bid/ask; we use an OHLC range proxy instead.
      # Option candles can have large ranges, so keep this permissive by default.
      max_spread_pct: 60.0
    },
    ignore_last_signal_bars: 0
  }.freeze

  BUY_SIGNALS = ["BUY CALLS", "BUY PUTS"].freeze

  def initialize(policy_config: {}, config: {}, option_data_provider: nil)
    @policy = OptionsBuyingPolicy.new(config: policy_config)
    @config = deep_merge(DEFAULT_CONFIG, config)
    @option_data_provider = option_data_provider || method(:fetch_expired_option_data)
  end

  def run(instrument:, signals:, interval:)
    trades = []
    skip_log = []
    candles_cache = {}
    flip_times = build_flip_times(signals)

    eligible_signals = signals[0...[signals.size - @config[:ignore_last_signal_bars].to_i, 0].max]

    signal_start_time = eligible_signals.first&.dig(:timestamp)
    signal_end_time = eligible_signals.last&.dig(:timestamp)

    expired_from_date = (signal_start_time || Time.now).to_date.strftime("%Y-%m-%d")
    expired_to_date = (signal_end_time || Time.now).to_date.strftime("%Y-%m-%d")
    expired_to_date = (Date.parse(expired_to_date) + 1).strftime("%Y-%m-%d")

    expired_from_date = nearest_trading_day(expired_from_date)
    expired_from_date, expired_to_date = cap_expired_date_range(expired_from_date, expired_to_date)

    eligible_signals.each do |signal_row|
      next unless BUY_SIGNALS.include?(signal_row[:signal])

      policy = @policy.recommendation(
        signal: signal_row[:signal],
        adx: signal_row[:adx],
        atr_pct: signal_row[:atr_pct]
      )
      if policy[:decision] == :no_trade
        skip_log << skip_row(signal_row, policy[:reason])
        next
      end

      side = policy[:side]
      strike_rule = strike_expression(policy[:moneyness], side)
      option_type = side == :ce ? "CALL" : "PUT"
      cache_key = [instrument.security_id.to_i, option_type, strike_rule, interval.to_s]
      option_candles = candles_cache[cache_key] ||= @option_data_provider.call(
        security_id: instrument.security_id.to_i,
        exchange_segment: @config[:options_exchange_segment],
        interval: interval.to_s,
        expiry_flag: @config[:expiry_flag],
        expiry_code: @config[:expiry_code],
        strike: strike_rule,
        option_type: option_type,
        from_date: expired_from_date,
        to_date: expired_to_date
      )
      if option_candles.empty?
        skip_log << skip_row(signal_row, "no option candles for #{option_type} #{strike_rule}")
        next
      end

      trade, skip_reason = simulate_trade(
        signal_row: signal_row,
        option_candles: option_candles,
        side: side,
        strike_rule: strike_rule,
        flip_times: flip_times
      )
      if trade
        trades << trade
      else
        skip_log << skip_row(signal_row, skip_reason || "no valid entry candle after signal")
      end
    end

    summary = build_summary(trades, skip_log)
    { trades: trades, summary: summary, skips: skip_log }
  end

  def write_trades_csv(path, trades)
    return if trades.empty?

    headers = trades.first.keys
    CSV.open(path, "w") do |csv|
      csv << headers
      trades.each { |trade| csv << headers.map { |key| trade[key] } }
    end
  end

  def write_summary_json(path, summary)
    File.write(path, JSON.pretty_generate(summary))
  end

  private

  def simulate_trade(signal_row:, option_candles:, side:, strike_rule:, flip_times:)
    signal_time = signal_row[:timestamp]
    entry_index = option_candles.find_index { |candle| candle[:timestamp] >= signal_time }
    return [nil, "no option candle after signal"] if entry_index.nil?

    entry_candle = option_candles[entry_index]
    return [nil, "liquidity gate failed"] unless liquid_entry?(entry_candle)

    entry_price = entry_candle[:open].to_f
    return [nil, "invalid entry price"] if entry_price <= 0.0

    sl_price, tp_price = risk_prices(entry_price)
    exit_data = find_exit(
      option_candles: option_candles,
      entry_index: entry_index,
      side: side,
      signal_time: signal_time,
      flip_times: flip_times,
      sl_price: sl_price,
      tp_price: tp_price
    )

    pnl_points = side == :ce ? (exit_data[:price] - entry_price) : (entry_price - exit_data[:price])
    pnl_pct = entry_price.zero? ? 0.0 : (pnl_points / entry_price) * 100.0

    [
      {
      signal_time: signal_time,
      side: side,
      strike_rule: strike_rule,
      entry_time: entry_candle[:timestamp],
      entry_price: entry_price.round(4),
      exit_time: exit_data[:timestamp],
      exit_price: exit_data[:price].round(4),
      bars_held: exit_data[:bars_held],
      exit_reason: exit_data[:reason],
      pnl_points: pnl_points.round(4),
      pnl_pct: pnl_pct.round(4),
      option_oi_at_entry: entry_candle[:open_interest].to_f.round(2),
      option_volume_at_entry: entry_candle[:volume].to_f.round(2)
      },
      nil
    ]
  end

  def find_exit(option_candles:, entry_index:, side:, signal_time:, flip_times:, sl_price:, tp_price:)
    max_hold = @config.dig(:risk, :max_hold_bars).to_i
    entry_time = option_candles[entry_index][:timestamp]
    opposite_flip_time = first_opposite_flip_after(flip_times, side, signal_time)

    (1..max_hold).each do |offset|
      index = entry_index + offset
      break if index >= option_candles.size

      candle = option_candles[index]
      intrabar_exit = intrabar_exit_for(candle: candle, side: side, sl_price: sl_price, tp_price: tp_price)
      if intrabar_exit
        return { timestamp: candle[:timestamp], price: intrabar_exit[:price], reason: intrabar_exit[:reason], bars_held: offset }
      end

      if opposite_flip_time && candle[:timestamp] >= opposite_flip_time
        return { timestamp: candle[:timestamp], price: candle[:close].to_f, reason: "signal_flip", bars_held: offset }
      end
    end

    max_exit_index = [entry_index + max_hold, option_candles.size - 1].min
    fallback_candle = option_candles[max_exit_index]
    {
      timestamp: fallback_candle[:timestamp],
      price: fallback_candle[:close].to_f,
      reason: "max_hold_bars",
      bars_held: max_exit_index - entry_index
    }
  end

  def intrabar_exit_for(candle:, side:, sl_price:, tp_price:)
    low = candle[:low].to_f
    high = candle[:high].to_f

    if side == :ce
      return { reason: "stop_loss", price: sl_price } if low <= sl_price
      return { reason: "take_profit", price: tp_price } if high >= tp_price
    else
      return { reason: "stop_loss", price: sl_price } if high >= sl_price
      return { reason: "take_profit", price: tp_price } if low <= tp_price
    end

    nil
  end

  def liquid_entry?(candle)
    oi = candle[:open_interest].to_f
    return false if oi < @config.dig(:liquidity, :min_oi).to_f

    spread_proxy = spread_proxy_pct(candle)
    return false if spread_proxy > @config.dig(:liquidity, :max_spread_pct).to_f

    true
  end

  def spread_proxy_pct(candle)
    open = candle[:open].to_f
    high = candle[:high].to_f
    low = candle[:low].to_f
    return 99.0 if open <= 0.0

    ((high - low) / open) * 100.0
  end

  def risk_prices(entry_price)
    sl_pct = @config.dig(:risk, :sl_pct).to_f
    tp_pct = @config.dig(:risk, :tp_pct).to_f
    sl_price = entry_price * (1.0 - sl_pct)
    tp_price = entry_price * (1.0 + tp_pct)
    [sl_price, tp_price]
  end

  def build_flip_times(signals)
    {
      ce: signals.select { |row| row[:signal] == "BUY PUTS" }.map { |row| row[:timestamp] },
      pe: signals.select { |row| row[:signal] == "BUY CALLS" }.map { |row| row[:timestamp] }
    }
  end

  def first_opposite_flip_after(flip_times, side, signal_time)
    flip_times.fetch(side).find { |timestamp| timestamp > signal_time }
  end

  def strike_expression(moneyness, side)
    return "ATM" if moneyness == :atm
    return side == :ce ? "ATM-1" : "ATM+1" if moneyness == :itm

    side == :ce ? "ATM+1" : "ATM-1"
  end

  def fetch_expired_option_data(security_id:, exchange_segment:, interval:, expiry_flag:, expiry_code:, strike:, option_type:, from_date:, to_date:)
    data = DhanHQ::Models::ExpiredOptionsData.fetch(
      exchange_segment: exchange_segment,
      interval: interval,
      security_id: security_id,
      instrument: "OPTIDX",
      expiry_flag: expiry_flag,
      expiry_code: expiry_code,
      strike: strike,
      drv_option_type: option_type,
      required_data: %w[open high low close volume oi strike spot iv],
      from_date: from_date,
      to_date: to_date
    )
    data.to_candles(option_type)
  rescue StandardError
    []
  end

  def nearest_trading_day(date_string)
    date = Date.parse(date_string)
    return (date - 1).strftime("%Y-%m-%d") if date.saturday?
    return (date - 2).strftime("%Y-%m-%d") if date.sunday?

    date.strftime("%Y-%m-%d")
  end

  def cap_expired_date_range(from_date_string, to_date_string)
    from_date = Date.parse(from_date_string)
    to_date = Date.parse(to_date_string)

    return [from_date_string, to_date_string] if (to_date - from_date).to_i <= 31

    capped_from = (to_date - 30) # keep (to - from) <= 31 (non-inclusive to_date)
    [capped_from.strftime("%Y-%m-%d"), to_date_string]
  end

  def build_summary(trades, skip_log)
    gross_profit = trades.select { |trade| trade[:pnl_points] > 0 }.sum { |trade| trade[:pnl_points] }
    gross_loss = trades.select { |trade| trade[:pnl_points] < 0 }.sum { |trade| trade[:pnl_points].abs }
    net_pnl = gross_profit - gross_loss
    wins = trades.count { |trade| trade[:pnl_points] > 0 }
    losses = trades.count { |trade| trade[:pnl_points] <= 0 }
    win_rate = trades.empty? ? 0.0 : wins.to_f / trades.size
    profit_factor = gross_loss.zero? ? 99.0 : gross_profit / gross_loss
    avg_pnl = trades.empty? ? 0.0 : net_pnl / trades.size

    equity = 0.0
    peak = 0.0
    max_drawdown = 0.0
    trades.each do |trade|
      equity += trade[:pnl_points]
      peak = [peak, equity].max
      max_drawdown = [max_drawdown, peak - equity].max
    end

    {
      trades: trades.size,
      wins: wins,
      losses: losses,
      win_rate: win_rate.round(6),
      gross_profit: gross_profit.round(6),
      gross_loss: gross_loss.round(6),
      net_pnl: net_pnl.round(6),
      profit_factor: profit_factor.round(6),
      max_drawdown: max_drawdown.round(6),
      avg_pnl: avg_pnl.round(6),
      expectancy: avg_pnl.round(6),
      skipped_signals: skip_log.size
    }
  end

  def skip_row(signal_row, reason)
    { signal_time: signal_row[:timestamp], signal: signal_row[:signal], reason: reason }
  end

  def deep_merge(base, overrides)
    base.merge(overrides) do |_key, left, right|
      left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
    end
  end
end
