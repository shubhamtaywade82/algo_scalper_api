#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(__dir__, "..", "lib")

require "optparse"
require "json"
require "fileutils"
require "time"
require "dhan_hq_api_bars"
require "super_trend_signal_generator"
require "options_backtester"

options = {
  exchange_segment: "IDX_I",
  symbol: "NIFTY",
  interval: "1",
  days: 20,
  tf_minutes: 1,
  policy_json: nil,
  sl_pct: 0.30,
  tp_pct: 0.60,
  max_hold_bars: 20,
  ignore_last_signal_bars: 1,
  min_oi: 1_000,
  max_spread_pct: 60.0,
  expiry_flag: "WEEK",
  expiry_code: 1,
  preset: nil,
  out_dir: File.join(__dir__, "..", "tmp", "optimization")
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/backtest_options.rb [options]"
  opts.on("--exchange-segment SEG", "Exchange segment (e.g. IDX_I)") { |v| options[:exchange_segment] = v }
  opts.on("--symbol SYMBOL", "Instrument symbol (e.g. NIFTY)") { |v| options[:symbol] = v }
  opts.on("--interval INT", "Candle interval in minutes") { |v| options[:interval] = v }
  opts.on("--days N", Integer, "How many days back from today") { |v| options[:days] = v }
  opts.on("--tf-minutes N", Integer, "Signal timeframe minutes") { |v| options[:tf_minutes] = v }
  opts.on("--policy-json PATH", "Calibrated policy JSON path") { |v| options[:policy_json] = v }
  opts.on("--sl-pct N", Float, "Stop loss percent (0.30 means 30%)") { |v| options[:sl_pct] = v }
  opts.on("--tp-pct N", Float, "Take profit percent (0.60 means 60%)") { |v| options[:tp_pct] = v }
  opts.on("--max-hold-bars N", Integer, "Maximum bars to hold") { |v| options[:max_hold_bars] = v }
  opts.on("--ignore-last-signal-bars N", Integer, "Ignore last N signal bars to avoid no-entry tail signals") { |v| options[:ignore_last_signal_bars] = v }
  opts.on("--min-oi N", Integer, "Minimum open interest at entry") { |v| options[:min_oi] = v }
  opts.on("--max-spread-pct N", Float, "Maximum spread proxy percent at entry") { |v| options[:max_spread_pct] = v }
  opts.on("--expiry-flag FLAG", "WEEK or MONTH") { |v| options[:expiry_flag] = v.upcase }
  opts.on("--expiry-code N", Integer, "Expiry code (fixed default 1)") { |v| options[:expiry_code] = v }
  opts.on("--preset PRESET", "Preset: scalping (tight SL/TP + short hold)") { |v| options[:preset] = v }
  opts.on("--out-dir DIR", "Output directory") { |v| options[:out_dir] = v }
end.parse!

apply_scalping_policy_default = false
if options[:preset].to_s.downcase == "scalping"
  apply_scalping_policy_default = options[:policy_json].nil?

  # Tight risk + short holds for 1-minute intraday scalping.
  options[:tf_minutes] = 1 unless ARGV.include?("--tf-minutes")
  options[:interval] = "1" unless ARGV.include?("--interval")

  options[:sl_pct] = 0.015 unless ARGV.include?("--sl-pct")
  options[:tp_pct] = 0.030 unless ARGV.include?("--tp-pct")
  options[:max_hold_bars] = 5 unless ARGV.include?("--max-hold-bars")
  options[:ignore_last_signal_bars] = 2 unless ARGV.include?("--ignore-last-signal-bars")

  options[:min_oi] = 5_000 unless ARGV.include?("--min-oi")
  options[:max_spread_pct] = 80.0 unless ARGV.include?("--max-spread-pct")
end

api_data = DhanHqApiBars.new.fetch(
  exchange_segment: options[:exchange_segment],
  symbol: options[:symbol],
  interval: options[:interval],
  days: options[:days]
)
bars = api_data[:bars]
abort "No bars loaded" if bars.empty?

signals = SuperTrendSignalGenerator.new(tf_minutes: options[:tf_minutes]).generate(bars).reject { |r| r[:warmup] }

policy_config = if options[:policy_json]
                  parsed = JSON.parse(File.read(options[:policy_json]))
                  parsed["policy"] || {}
                else
                  {}
                end

if apply_scalping_policy_default
  policy_config = {
    min_trend_adx: 22.0,
    moderate_trend_adx: 25.0,
    strong_trend_adx: 35.0,
    preferred_moneyness: { ce: :otm, pe: :otm }
  }
end

backtester = OptionsBacktester.new(
  policy_config: policy_config,
  config: {
    expiry_flag: options[:expiry_flag],
    expiry_code: options[:expiry_code],
    risk: {
      sl_pct: options[:sl_pct],
      tp_pct: options[:tp_pct],
      max_hold_bars: options[:max_hold_bars]
    },
    ignore_last_signal_bars: options[:ignore_last_signal_bars],
    liquidity: {
      min_oi: options[:min_oi],
      max_spread_pct: options[:max_spread_pct]
    }
  }
)

result = backtester.run(instrument: api_data[:instrument], signals: signals, interval: options[:interval])

FileUtils.mkdir_p(options[:out_dir])
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
trades_csv = File.join(options[:out_dir], "options_trades_#{timestamp}.csv")
summary_json = File.join(options[:out_dir], "options_summary_#{timestamp}.json")
backtester.write_trades_csv(trades_csv, result[:trades])
backtester.write_summary_json(summary_json, result[:summary].merge(skips: result[:skips]))

puts "Resolved instrument: #{api_data[:instrument].exchange_segment}:#{api_data[:instrument].security_id} #{api_data[:instrument].display_name}"
puts "Bars: #{bars.size}, Signals: #{signals.size}"
puts "Trades: #{result[:summary][:trades]}, Skipped signals: #{result[:summary][:skipped_signals]}"
puts "Net PnL: #{result[:summary][:net_pnl]}, Win rate: #{(result[:summary][:win_rate] * 100).round(2)}%"
puts "Trades CSV: #{trades_csv}"
puts "Summary JSON: #{summary_json}"
