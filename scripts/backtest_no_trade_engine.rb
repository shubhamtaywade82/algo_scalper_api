#!/usr/bin/env ruby
# frozen_string_literal: true

# Example script for running No-Trade Engine backtest
# Usage: bundle exec ruby scripts/backtest_no_trade_engine.rb [SYMBOL] [DAYS]

require_relative '../config/environment'

symbol = ARGV[0] || 'NIFTY'
days = (ARGV[1] || 90).to_i

puts "\n#{'=' * 80}"
puts "BACKTEST: #{symbol} with No-Trade Engine + Supertrend + ADX"
puts "Period: Last #{days} days"
puts '=' * 80

begin
  service = BacktestServiceWithNoTradeEngine.run(
    symbol: symbol,
    interval_1m: '1',
    interval_5m: '5',
    days_back: days,
    supertrend_cfg: {
      period: 7,
      multiplier: 3.0
    },
    adx_min_strength: 0 # Let No-Trade Engine handle filtering
  )

  service.print_summary

  # Save results
  results_file = Rails.root.join("tmp/backtest_no_trade_engine_#{symbol.downcase}_#{Time.zone.today}.json")
  File.write(results_file, JSON.pretty_generate(service.summary))
  puts "\n✅ Results saved to: #{results_file}"
rescue StandardError => e
  puts "\n❌ Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(10).join("\n")
  exit 1
end
