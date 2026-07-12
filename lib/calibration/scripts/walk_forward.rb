#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(__dir__, "..", "lib")

require "optparse"
require "fileutils"
require "strategy_optimization"

options = {
  exchange_segment: "IDX_I",
  symbol: "NIFTY",
  interval: "1",
  days: 60,
  tf_minutes: 1,
  trials: 200,
  seed: 42,
  train_days: 20,
  validate_days: 5,
  top_n: 5,
  min_trades: 3,
  max_drawdown: 1_000_000.0,
  out_dir: File.join(__dir__, "..", "tmp", "optimization")
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/walk_forward.rb [options]"
  opts.on("--exchange-segment SEG", "Exchange segment (e.g. IDX_I, NSE_EQ)") { |value| options[:exchange_segment] = value }
  opts.on("--symbol SYMBOL", "Instrument symbol (e.g. NIFTY, RELIANCE)") { |value| options[:symbol] = value }
  opts.on("--interval INT", "Candle interval in minutes") { |value| options[:interval] = value }
  opts.on("--days N", Integer, "How many days back from today") { |value| options[:days] = value }
  opts.on("--tf-minutes N", Integer, "Strategy timeframe minutes") { |value| options[:tf_minutes] = value }
  opts.on("--trials N", Integer, "Random parameter combinations per fold") { |value| options[:trials] = value }
  opts.on("--seed N", Integer, "Random seed") { |value| options[:seed] = value }
  opts.on("--train-days N", Integer, "Training window in trading days") { |value| options[:train_days] = value }
  opts.on("--validate-days N", Integer, "Validation window in trading days") { |value| options[:validate_days] = value }
  opts.on("--top-n N", Integer, "Top train configs to revalidate per fold") { |value| options[:top_n] = value }
  opts.on("--min-trades N", Integer, "Reject configs below trade count") { |value| options[:min_trades] = value }
  opts.on("--max-drawdown N", Float, "Reject configs above drawdown") { |value| options[:max_drawdown] = value }
  opts.on("--out-dir DIR", "Output directory for CSV") { |value| options[:out_dir] = value }
end.parse!

StrategyOptimization.load_env!(File.expand_path("..", __dir__))

api_data = StrategyOptimization.load_bars(
  exchange_segment: options[:exchange_segment],
  symbol: options[:symbol],
  interval: options[:interval],
  days: options[:days]
)
bars = api_data[:bars]

abort "No bars loaded" if bars.empty?

folds = StrategyOptimization.build_walk_forward_folds(
  bars: bars,
  interval: options[:interval],
  train_days: options[:train_days],
  validate_days: options[:validate_days]
)
abort "Not enough bars for the requested walk-forward windows" if folds.empty?

rng = Random.new(options[:seed])
fold_rows = []
all_best_params = []

folds.each_with_index do |fold, fold_index|
  configs = StrategyOptimization.sample_configs(trials: options[:trials], rng: rng)
  trained = configs.map do |params|
    StrategyOptimization.evaluate_config(bars: fold[:train], tf_minutes: options[:tf_minutes], params: params)
  end

  constrained_train = trained.select do |row|
    StrategyOptimization.constraints_satisfied?(
      row,
      min_trades: options[:min_trades],
      max_drawdown: options[:max_drawdown]
    )
  end
  next if constrained_train.empty?

  top_candidates = constrained_train.sort_by { |row| -row[:score] }.first(options[:top_n])
  validated_candidates = top_candidates.map do |candidate|
    validate_stats = StrategyOptimization.evaluate_config(
      bars: fold[:validate],
      tf_minutes: options[:tf_minutes],
      params: candidate[:params]
    )
    { train: candidate, validate: validate_stats }
  end

  best_pair = validated_candidates.max_by { |pair| pair[:validate][:score] }
  best_train = best_pair[:train]
  validate_stats = best_pair[:validate]

  all_best_params << best_train[:params]

  fold_rows << {
    fold: fold_index + 1,
    train_bars: fold[:train].size,
    validate_bars: fold[:validate].size,
    train_score: best_train[:score],
    validate_score: validate_stats[:score],
    train_net_pnl: best_train[:net_pnl],
    validate_net_pnl: validate_stats[:net_pnl],
    train_win_rate: best_train[:win_rate],
    validate_win_rate: validate_stats[:win_rate],
    train_drawdown: best_train[:max_drawdown],
    validate_drawdown: validate_stats[:max_drawdown],
    train_trades: best_train[:trade_count],
    validate_trades: validate_stats[:trade_count],
    best_params: best_train[:params],
    top_candidates_considered: top_candidates.size
  }
end

abort "No fold produced candidates satisfying constraints" if fold_rows.empty?

parameter_frequency = all_best_params.each_with_object(Hash.new(0)) { |params, acc| acc[params] += 1 }
stable_params = parameter_frequency.max_by { |_, count| count }&.first
abort "Could not determine stable parameters" if stable_params.nil?

full_eval = StrategyOptimization.evaluate_config(
  bars: bars,
  tf_minutes: options[:tf_minutes],
  params: stable_params
)

FileUtils.mkdir_p(options[:out_dir])
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
fold_csv_path = File.join(options[:out_dir], "walk_forward_folds_#{timestamp}.csv")
recommended_json_path = File.join(options[:out_dir], "recommended_config_#{timestamp}.json")

fold_export = fold_rows.map do |row|
  flat = row.dup
  params = flat.delete(:best_params)
  flat.merge(params.transform_keys { |key| "param_#{key}".to_sym })
end
StrategyOptimization.write_results_csv(fold_csv_path, fold_export)

recommended_payload = {
  generated_at: Time.now.utc.iso8601,
  stable_params: stable_params,
  tf_minutes: options[:tf_minutes],
  source_window: {
    exchange_segment: options[:exchange_segment],
    symbol: options[:symbol],
    security_id: api_data[:instrument].security_id,
    interval: options[:interval],
    from: api_data[:from_date].strftime("%Y-%m-%d"),
    to: api_data[:to_date].strftime("%Y-%m-%d")
  },
  walk_forward: {
    folds: folds.size,
    folds_used: fold_rows.size,
    train_days: options[:train_days],
    validate_days: options[:validate_days],
    trials_per_fold: options[:trials],
    top_n_revalidated: options[:top_n],
    min_trades: options[:min_trades],
    max_drawdown: options[:max_drawdown]
  },
  full_period_metrics: full_eval.reject { |key, _| key == :params }
}
StrategyOptimization.write_json(recommended_json_path, recommended_payload)

puts "Loaded bars: #{bars.size}"
puts "Resolved instrument: #{api_data[:instrument].exchange_segment}:#{api_data[:instrument].security_id} #{api_data[:instrument].display_name}"
puts "Date range: #{api_data[:from_date]} -> #{api_data[:to_date]} (#{options[:days]} days)"
puts "Folds: #{folds.size}"
puts "Train days: #{options[:train_days]}, Validate days: #{options[:validate_days]}"
puts "Trials per fold: #{options[:trials]}"
puts "Top-N revalidated per fold: #{options[:top_n]}"
puts "Constraint filters: min_trades=#{options[:min_trades]}, max_drawdown=#{options[:max_drawdown]}"
puts "Stable params (most frequent fold winner): #{stable_params}"
puts "Full-period score with stable params: #{full_eval[:score].round(4)}"
puts "Full-period net PnL: #{full_eval[:net_pnl].round(2)}"
puts "Full-period max drawdown: #{full_eval[:max_drawdown].round(2)}"
puts "Fold CSV: #{fold_csv_path}"
puts "Recommended JSON: #{recommended_json_path}"
