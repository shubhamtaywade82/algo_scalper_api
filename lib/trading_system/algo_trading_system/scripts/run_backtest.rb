# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative '../src/backtest/orchestrator'

# Use defaults but allow override
options = {
  underlying: 'nifty',
  strategy: :scalper_strategy,
  from_date: (Date.today - 30).to_s,
  to_date: (Date.today - 1).to_s,
  option_type: 'CALL',
  strikes: ['ATM'],
  interval: '5',
  capital: 1_000_000
}

# Load the strategy_config.yml
config_path = File.join(Dir.pwd, 'config', 'strategy_config.yml')
if File.exist?(config_path)
  strategy_params = YAML.load_file(config_path)
  options[:strategy_params] = strategy_params
end

# Silencing standard logging to keep stdout clean for JSON
# (assuming logger output can be redirected or silenced)
# But here we'll just capture the return value

orchestrator = Backtest::Orchestrator.new(
  access_token: ENV['DHAN_ACCESS_TOKEN'] || 'MOCK_TOKEN',
  capital: options[:capital]
)

begin
  if ENV['DHAN_ACCESS_TOKEN'] == 'MOCK_TOKEN' || ENV['DHAN_ACCESS_TOKEN'].nil?
    # Generate random results for testing AutoExp loop
    summary = {
      profit_factor: rand(0.8..2.5).round(2),
      drawdown: rand(0.05..0.30).round(2),
      total_pnl_val: rand(1000..50000),
      win_rate: "#{rand(40..70)}%"
    }
  else
    results = orchestrator.run_backtest(config: options)
    
    # Pick the summary from the first strike (or aggregate further if needed)
    first_strike = results[:by_strike].keys.first
    summary = results[:by_strike][first_strike][:summary]
  end
  
  # Add aggregate fields if needed
  output = {
    profit_factor: summary[:profit_factor],
    drawdown: summary[:drawdown],
    total_pnl: summary[:total_pnl_val],
    win_rate: summary[:win_rate]
  }
  
  puts output.to_json
rescue StandardError => e
  STDERR.puts "Error: #{e.message}"
  exit 1
end
