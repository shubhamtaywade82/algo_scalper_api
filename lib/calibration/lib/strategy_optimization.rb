# frozen_string_literal: true

require "csv"
require "json"
require "time"
require_relative "super_trend_signal_generator"
require_relative "dhan_hq_api_bars"

module StrategyOptimization
  INTRADAY_MINUTES_PER_DAY = 375.0
  ENTRY_SIGNAL_TO_SIDE = {
    "BUY CALLS" => :calls,
    "BUY PUTS" => :puts
  }.freeze

  EXIT_SIGNAL_BY_SIDE = {
    calls: "BOOK CALL PROFITS",
    puts: "BOOK PUT PROFITS"
  }.freeze

  PARAM_SPACE = {
    st_factor: [1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0],
    rsi_length: [10, 14, 21],
    atr_length: [10, 14, 21],
    adx_length: [10, 14, 21],
    adx_smoothing: [10, 14, 21],
    use_wicks: [true, false],
    disinterest_level: [10, 12, 14, 16, 18, 20, 22],
    trend_level: [18, 22, 26, 30, 34, 38, 40]
  }.freeze

  module_function

  def load_env!(root_dir)
    env_file = File.join(root_dir, ".env")
    return unless File.file?(env_file)

    File.foreach(env_file) do |line|
      next if line.strip.empty? || line.start_with?("#")

      key, value = line.strip.split("=", 2)
      ENV[key] ||= value
    end
  end

  def load_bars(exchange_segment:, symbol:, interval:, days:)
    loader = DhanHqApiBars.new
    loader.fetch(
      exchange_segment: exchange_segment,
      symbol: symbol,
      interval: interval,
      days: days
    )
  end

  def sample_configs(trials:, rng:, space: PARAM_SPACE)
    Array.new(trials) do
      space.each_with_object({}) do |(key, values), acc|
        acc[key] = values[rng.rand(values.length)]
      end
    end
  end

  def evaluate_config(bars:, tf_minutes:, params:)
    generator = SuperTrendSignalGenerator.new(params.merge(tf_minutes: tf_minutes))
    results = generator.generate(bars).reject { |row| row[:warmup] }
    stats = compute_trade_stats(results)
    stats.merge(params: params)
  end

  def compute_trade_stats(results)
    trades, max_drawdown = extract_trades(results)
    gross_profit = trades.select { |trade| trade[:pnl] > 0 }.sum { |trade| trade[:pnl] }
    gross_loss = trades.select { |trade| trade[:pnl] < 0 }.sum { |trade| trade[:pnl].abs }
    trade_count = trades.length
    win_count = trades.count { |trade| trade[:pnl] > 0 }
    win_rate = trade_count.zero? ? 0.0 : win_count.to_f / trade_count
    net_pnl = gross_profit - gross_loss
    avg_pnl = trade_count.zero? ? 0.0 : net_pnl / trade_count
    profit_factor = gross_loss.zero? ? 99.0 : (gross_profit / gross_loss)
    score = strategy_score(net_pnl: net_pnl, win_rate: win_rate, max_drawdown: max_drawdown, trade_count: trade_count, profit_factor: profit_factor)

    {
      trade_count: trade_count,
      win_count: win_count,
      loss_count: trade_count - win_count,
      win_rate: win_rate,
      gross_profit: gross_profit,
      gross_loss: gross_loss,
      net_pnl: net_pnl,
      avg_pnl_per_trade: avg_pnl,
      max_drawdown: max_drawdown,
      profit_factor: profit_factor,
      score: score
    }
  end

  def write_results_csv(path, rows)
    return if rows.empty?

    headers = rows.first.keys
    CSV.open(path, "w") do |csv|
      csv << headers
      rows.each { |row| csv << headers.map { |key| row[key] } }
    end
  end

  def write_json(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end

  def bars_per_day(interval)
    int = interval.to_i
    raise ArgumentError, "Only minute intervals are supported for walk-forward" if int <= 0

    (INTRADAY_MINUTES_PER_DAY / int).floor
  end

  def build_walk_forward_folds(bars:, interval:, train_days:, validate_days:)
    per_day = bars_per_day(interval)
    train_size = per_day * train_days
    validate_size = per_day * validate_days
    folds = []
    start_index = 0

    while (start_index + train_size + validate_size) <= bars.length
      train_slice = bars[start_index, train_size]
      validate_slice = bars[start_index + train_size, validate_size]
      folds << { train: train_slice, validate: validate_slice, start_index: start_index }
      start_index += validate_size
    end

    folds
  end

  def flatten_result(result)
    params = result[:params]
    result.reject { |key, _| key == :params }.merge(params.transform_keys { |k| "param_#{k}".to_sym })
  end

  def constraints_satisfied?(result, min_trades:, max_drawdown:)
    return false if result[:trade_count] < min_trades
    return false if result[:max_drawdown] > max_drawdown

    true
  end

  def strategy_score(net_pnl:, win_rate:, max_drawdown:, trade_count:, profit_factor:)
    return -1_000_000 if trade_count < 3

    adjusted_pf = [profit_factor, 5.0].min
    (net_pnl * 0.6) + (win_rate * 1000.0 * 0.25) + (adjusted_pf * 100.0 * 0.15) - (max_drawdown * 0.5)
  end

  def build_entry(signal, close, timestamp)
    side = ENTRY_SIGNAL_TO_SIDE[signal]
    return nil if side.nil?

    { side: side, entry_price: close, entry_time: timestamp }
  end

  def exit_signal_for(side)
    EXIT_SIGNAL_BY_SIDE.fetch(side)
  end

  def trade_pnl(side:, entry_price:, exit_price:)
    side == :calls ? (exit_price - entry_price) : (entry_price - exit_price)
  end

  def extract_trades(results)
    open_trade = nil
    trades = []
    equity_curve = []
    cumulative_pnl = 0.0

    results.each do |row|
      open_trade = build_entry(row[:signal], row[:close].to_f, row[:timestamp]) if open_trade.nil?
      next if open_trade.nil?
      next unless exit_signal_for(open_trade[:side]) == row[:signal]

      trade = close_trade(open_trade, row)
      trades << trade
      cumulative_pnl += trade[:pnl]
      equity_curve << cumulative_pnl
      open_trade = nil
    end

    [trades, calculate_max_drawdown(equity_curve)]
  end

  def close_trade(open_trade, row)
    pnl = trade_pnl(
      side: open_trade[:side],
      entry_price: open_trade[:entry_price],
      exit_price: row[:close].to_f
    )
    open_trade.merge(exit_price: row[:close].to_f, exit_time: row[:timestamp], pnl: pnl)
  end

  def calculate_max_drawdown(equity_curve)
    peak = 0.0
    max_drawdown = 0.0

    equity_curve.each do |equity|
      peak = [peak, equity].max
      max_drawdown = [max_drawdown, peak - equity].max
    end

    max_drawdown
  end

end
