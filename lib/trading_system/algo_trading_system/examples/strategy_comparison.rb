# frozen_string_literal: true

require_relative '../src/backtest/orchestrator'
require_relative '../src/strategies/trading_strategies'
require 'time'
require 'dotenv/load'
require 'terminal-table'

puts "╔════════════════════════════════════════════════════════════════════════════╗"
puts "║          NSE OPTIONS STRATEGY COMPARISON - REAL HISTORICAL DATA            ║"
puts "╚════════════════════════════════════════════════════════════════════════════╝"

# 1. Environment Check
token = ENV['DHAN_ACCESS_TOKEN']
if token.nil? || token.empty? || token == 'YOUR_ACCESS_TOKEN_HERE'
  puts "❌ ERROR: DHAN_ACCESS_TOKEN not found in .env file."
  puts "Please run 'bin/setup_auth' or add your token manually to .env"
  exit 1
end

# 2. Configuration
CONFIG = {
  underlying: 'nifty',
  from_date: (Date.today - 7).to_s,
  to_date: (Date.today - 1).to_s,
  capital: 1_000_000,
  strikes: ['ATM', 'ATM+1', 'ATM-1'],
  interval: 5
}.freeze

# 3. Initialize Orchestrator
orchestrator = Backtest::Orchestrator.new(
  access_token: token,
  capital: CONFIG[:capital],
  output_dir: './backtest_results/real_comparisons'
)

# 4. Strategy List
strategies = TradingStrategies::StrategyFactory.available_strategies
comparison_results = []

puts "📊 Configuration:"
puts "   Underlying: #{CONFIG[:underlying].upcase}"
puts "   Period:     #{CONFIG[:from_date]} to #{CONFIG[:to_date]}"
puts "   Interval:   #{CONFIG[:interval]} min"
puts "   Strikes:    #{CONFIG[:strikes].join(', ')}"

# 5. Execution Loop
strategies.each do |strategy_name|
  puts "\n🧪 Processing Strategy: #{strategy_name.to_s.upcase}..."
  
  begin
    sleep 1 # Cooldown
    
    results = orchestrator.run_backtest(config: CONFIG.merge(strategy: strategy_name))
    
    if results.nil? || !results.is_a?(Hash)
      puts "  ⚠️  No valid results returned for #{strategy_name}"
      next
    end

    total_trades = results[:total_trades] || 0
    total_pnl = results[:total_pnl] || 0.0
    
    all_trades = results[:trades] || []
    wins = all_trades.count { |t| t[:status] == 'WIN' }
    win_rate = total_trades.positive? ? (wins.to_f / total_trades * 100).round(2) : 0
    
    # Safe metric extraction
    by_strike = results[:by_strike] || {}
    strike_values = by_strike.values
    
    avg_max_dd = 0.0
    avg_sharpe = 0.0
    
    if strike_values.any?
      avg_max_dd = strike_values.map { |v| v.dig(:summary, :max_drawdown).to_f }.sum / strike_values.size
      avg_sharpe = strike_values.map { |v| v.dig(:summary, :sharpe_ratio).to_f }.sum / strike_values.size
    end
    
    comparison_results << {
      name: strategy_name.to_s.upcase,
      trades: total_trades,
      win_rate: "#{win_rate}%",
      pnl: "₹#{total_pnl.to_f.round(2)}",
      max_dd: "#{avg_max_dd.round(2)}%",
      sharpe: avg_sharpe.round(2)
    }
  rescue StandardError => e
    puts "  ❌ Error processing #{strategy_name}: #{e.message}"
    puts e.backtrace.first(3)
  end
end

# 6. Final Report
if comparison_results.any?
  rows = comparison_results.map do |res|
    [res[:name], res[:trades], res[:win_rate], res[:pnl], res[:max_dd], res[:sharpe]]
  end

  table = Terminal::Table.new do |t|
    t.headings = ['Strategy', 'Trades', 'Win Rate', 'Total P&L', 'Avg Max DD', 'Avg Sharpe']
    t.rows = rows
    t.style = { border_i: 'x', border_y: '│', border_x: '─' }
  end

  puts "\n📊 REAL-WORLD COMPARISON REPORT:"
  puts table

  valid_comparisons = comparison_results.select { |r| r[:trades] > 0 }
  if valid_comparisons.any?
    best_pnl = valid_comparisons.max_by { |r| r[:pnl].gsub(/[^\d.-]/, '').to_f }
    puts "\n🏆 RECOMMENDATION: '#{best_pnl[:name]}' performed best on real data."
  else
    puts "\n🏆 RECOMMENDATION: No trades were taken by any strategy in this period."
  end
  puts "📂 Detailed strike-wise reports saved in ./backtest_results/real_comparisons/"
else
  puts "\n⚠️ No results generated. Check your API connectivity and date range."
end
