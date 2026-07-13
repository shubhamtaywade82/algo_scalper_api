#!/usr/bin/env ruby
# frozen_string_literal: true

env_file = File.join(__dir__, ".env")
if File.file?(env_file)
  File.foreach(env_file) do |line|
    next if line.strip.empty? || line.start_with?("#")

    key, value = line.strip.split("=", 2)
    ENV[key] ||= value
  end
end

$LOAD_PATH.unshift File.join(__dir__, "lib")

require "optparse"
require "json"
require "super_trend_signal_generator"
require "dhan_hq_api_bars"

DEFAULT_OPTIONS = {
  exchange_segment: "IDX_I",
  symbol: "NIFTY",
  interval: "1",
  days: 60,
  tf_minutes: 5,
  signals_only: false,
  summary_only: false,
  no_color: false,
  last: nil
}.freeze

def parse_options
  options = DEFAULT_OPTIONS.dup

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby runner.rb [options]"
    opts.on("--exchange-segment SEG", "Exchange segment (e.g. IDX_I, NSE_EQ)") { |v| options[:exchange_segment] = v }
    opts.on("--symbol SYMBOL", "Instrument symbol (e.g. NIFTY, RELIANCE)") { |v| options[:symbol] = v }
    opts.on("--interval INT", "Candle interval (1,5,15,25,60)") { |v| options[:interval] = v }
    opts.on("--days N", Integer, "How many days back from today") { |v| options[:days] = v }
    opts.on("--tf-minutes N", Integer, "Timeframe minutes") { |v| options[:tf_minutes] = v }
    opts.on("--signals-only", "Only print non-HOLD bars") { options[:signals_only] = true }
    opts.on("--summary-only", "Skip row output, print only summary") { options[:summary_only] = true }
    opts.on("--no-color", "Disable ANSI colors") { options[:no_color] = true }
    opts.on("--last N", Integer, "Show last N bars") { |v| options[:last] = v }
  end.parse!

  options
end

def load_api_bars(options)
  loader = DhanHqApiBars.new
  loader.fetch(
    exchange_segment: options[:exchange_segment],
    symbol: options[:symbol],
    interval: options[:interval],
    days: options[:days]
  )
end

def filter_results(results, options)
  filtered_results = results.reject { |result| result[:warmup] }
  filtered_results = filtered_results.select { |result| result[:signal] != "HOLD" } if options[:signals_only]
  filtered_results = filtered_results.last(options[:last]) if options[:last]
  filtered_results
end

def print_rows(results, options)
  return if options[:summary_only]

  puts "\n#{'BAR'.ljust(9)} #{'TIMESTAMP'.ljust(22)} #{'CLOSE'.ljust(10)} #{'SIGNAL'.ljust(22)} #{'RSI'.ljust(8)} #{'ADX'.ljust(8)} #{'ATR%'.ljust(8)} #{'ST_DIR'.ljust(8)} MODE"
  puts "-" * 120

  results.each do |result|
    timestamp = result[:timestamp]&.strftime("%Y-%m-%d %H:%M") || "-"
    signal = result[:signal] || "-"
    direction = result[:st_direction] == -1 ? "BULL" : "BEAR"
    color = signal_color(signal, options)
    reset = color.empty? ? "" : "\e[0m"

    printf "#{color}%-9s %-22s %-10s %-22s %-8s %-8s %-8s %-8s %s#{reset}\n",
           result[:bar_index],
           timestamp,
           result[:close],
           signal,
           result[:rsi],
           result[:adx],
           result[:atr_pct],
           direction,
           result[:market_mode]
  end
end

def signal_color(signal, options)
  return "" if options[:no_color] || !STDOUT.tty?

  case signal
  when "BUY CALLS"
    "\e[32m"
  when "BUY PUTS"
    "\e[31m"
  when /BOOK/
    "\e[33m"
  else
    ""
  end
end

def print_summary(results)
  buy_call_count = results.count { |result| result[:signal] == "BUY CALLS" }
  buy_put_count = results.count { |result| result[:signal] == "BUY PUTS" }
  booked_profit_count = results.count { |result| result[:signal]&.include?("BOOK") }
  hold_count = results.count { |result| result[:signal] == "HOLD" }

  puts "\n-- Summary --------------------------------------------------"
  puts "  BUY CALLS:         #{buy_call_count}"
  puts "  BUY PUTS:          #{buy_put_count}"
  puts "  BOOK PROFITS:      #{booked_profit_count}"
  puts "  HOLD:              #{hold_count}"
  puts "  Total signal bars: #{results.size}"
end

options = parse_options
api_data = load_api_bars(options)
bars = api_data[:bars]
abort "No bars loaded" if bars.empty?

puts "Resolved instrument: #{api_data[:instrument].exchange_segment}:#{api_data[:instrument].security_id} #{api_data[:instrument].display_name}"
puts "Date range: #{api_data[:from_date]} -> #{api_data[:to_date]} (#{options[:days]} days)"
puts "Loaded #{bars.size} bars"

generator = SuperTrendSignalGenerator.new(tf_minutes: options[:tf_minutes])
results = filter_results(generator.generate(bars), options)

print_rows(results, options)
print_summary(results)