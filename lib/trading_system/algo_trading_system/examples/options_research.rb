# frozen_string_literal: true

require 'dotenv/load'
require_relative '../src/backtest/options_research_orchestrator'
require_relative '../src/utils/logger'

# Setup access token (Ensure DHAN_ACCESS_TOKEN is in .env)
access_token = ENV['DHAN_ACCESS_TOKEN']

unless access_token
  puts "Error: DHAN_ACCESS_TOKEN not found in .env"
  exit 1
end

orchestrator = Backtest::OptionsResearchOrchestrator.new(access_token: access_token)

# Example: Analyze Options for specified symbol, weeks, and expiry
# Usage: bundle exec ruby examples/options_research.rb [symbol] [weeks] [expiry_flag]
# Examples:
#   bundle exec ruby examples/options_research.rb nifty 2 WEEK
#   bundle exec ruby examples/options_research.rb banknifty 4 MONTH
#
# Default: nifty, 3 weeks, WEEK
symbol = (ARGV[0] || 'nifty').downcase.to_sym
weeks = (ARGV[1] || 3).to_i
expiry_flag = (ARGV[2] || 'WEEK').upcase

to_date = Date.today.to_s
from_date = (Date.today - (weeks * 7)).to_s

puts "Starting options research for #{symbol.upcase} for the past #{weeks} weeks (#{from_date} to #{to_date}) with #{expiry_flag} expiry..."

dataset = orchestrator.run_research(
  underlying: symbol,
  from_date: from_date,
  to_date: to_date,
  strike: 'ATM',
  interval: '1',
  expiry_flag: expiry_flag
)

if dataset.any?
  puts "Research complete! Captured #{dataset.size} combined candles."
  puts "First 5 rows of data:"
  dataset.first(5).each do |row|
    puts "Time: #{row[:timestamp]} | Spot: #{row[:spot_close]} | CE Close: #{row[:ce_close]} | PE Close: #{row[:pe_close]}"
  end
  puts "\nDataset has been saved to research_results/ directory."
else
  puts "No data found for the given range/criteria."
end
