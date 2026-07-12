# frozen_string_literal: true

require_relative '../src/backtest/orchestrator'
require 'time'
require 'ostruct'

# Mock DhanApiClient for local example without API key
class MockDhanApiClient < Api::DhanApiClient
  def fetch_expired_options(underlying:, from_date:, to_date:, **_opts)
    puts "Generating mock options data for #{underlying}..."
    start_time = Time.parse("#{from_date} 09:15:00 +0530")
    
    data = {}
    ['ATM', 'ATM+1', 'ATM-1'].each do |strike|
      strike_data = {
        timestamp: [], open: [], high: [], low: [], close: [],
        iv: [], oi: [], volume: [], spot: [], strike: []
      }
      current_price = 350.0 + rand(50)
      
      # Generate 1 day of 1m bars (375 minutes)
      (0...375).each do |i|
        ts = (start_time + (i * 60)).to_i
        # Create a trend followed by a dip to trigger RSI oversold
        bias = i < 100 ? -2.0 : 1.5
        change = (rand - 0.5) * 5.0 + bias
        open = current_price
        close = open + change
        high = [open, close].max + rand * 2.0
        low = [open, close].min - rand * 2.0
        current_price = close

        strike_data[:timestamp] << ts
        strike_data[:open] << open.round(2)
        strike_data[:high] << high.round(2)
        strike_data[:low] << low.round(2)
        strike_data[:close] << close.round(2)
        strike_data[:volume] << (5000 + rand(10000))
        strike_data[:iv] << (15.0 + rand(10.0))
        strike_data[:oi] << (100000 + rand(50000))
        strike_data[:spot] << (22000.0 + (i * 0.5))
        strike_data[:strike] << 22000.0
      end
      data["#{strike}_CALL"] = strike_data
    end
    data
  end
end

puts "╔════════════════════════════════════════════════════════════════════════════╗"
puts "║          NSE OPTIONS BACKTESTING ORCHESTRATOR - PRODUCTION                 ║"
puts "╚════════════════════════════════════════════════════════════════════════════╝"

# Configuration
CONFIG = {
  underlying: 'nifty',
  strategy: :rsi_macd,
  from_date: '2024-01-01',
  to_date: '2024-01-01',
  option_type: 'CALL',
  strikes: ['ATM', 'ATM+1', 'ATM-1'],
  interval: '1',
  expiry_flag: 'WEEK',
  access_token: 'MOCK_TOKEN'
}.freeze

# 1. Initialize Orchestrator with Mock Client
orchestrator = Backtest::Orchestrator.new(
  access_token: CONFIG[:access_token],
  capital: 1_000_000,
  output_dir: './backtest_results'
)

# Inject mock client for this example
mock_client = MockDhanApiClient.new(access_token: 'MOCK')
orchestrator.instance_variable_set(:@api_client, mock_client)

# 2. Run Multi-Strike Backtest
begin
  results = orchestrator.run_backtest(config: CONFIG)

  puts "\n📊 MULTI-STRIKE SUMMARY:"
  puts "────────────────────────────────────────────────"
  puts "Total Trades:      #{results[:total_trades]}"
  puts "Total P&L:         ₹#{results[:total_pnl]}"
  puts "Strikes Analyzed:  #{results[:strikes_analyzed]}"
  puts "────────────────────────────────────────────────"

  # Print summary per strike
  results[:by_strike].each do |strike, res|
    s = res[:summary]
    puts "#{strike.ljust(12)} | Trades: #{s[:total_trades].to_s.ljust(2)} | Win Rate: #{s[:win_rate].ljust(6)} | P&L: #{s[:total_pnl]}"
  end

  puts "\n✅ All backtests complete. View full reports in ./backtest_results/"
rescue StandardError => e
  puts "\n❌ Error during orchestrator run: #{e.message}"
  puts e.backtrace.first(5)
end
