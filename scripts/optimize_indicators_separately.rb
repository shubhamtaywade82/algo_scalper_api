# frozen_string_literal: true

# Script to optimize each indicator separately
# Usage: rails runner scripts/optimize_indicators_separately.rb [index_key] [interval] [lookback_days]
#
# Examples:
#   rails runner scripts/optimize_indicators_separately.rb NIFTY 5 45
#   rails runner scripts/optimize_indicators_separately.rb SENSEX 1 30

# Check if table exists
unless BestIndicatorParam.table_exists?
  puts "\n❌ ERROR: best_indicator_params table does not exist!"
  puts "\nPlease run the migration first:"
  puts '  rails db:migrate'
  exit 1
end

# Parse arguments
index_key = ARGV[0] || 'NIFTY'
interval = ARGV[1] || '5'
lookback_days = (ARGV[2] || '45').to_i

puts "\n" + ('=' * 80)
puts 'Single Indicator Parameter Optimization'
puts '=' * 80
puts "Index: #{index_key}"
puts "Interval: #{interval}m"
puts "Lookback: #{lookback_days} days"
puts ('=' * 80) + "\n"

# Get index configuration
algo_config = AlgoConfig.fetch
index_cfg = algo_config[:indices]&.find { |i| i[:key] == index_key }

unless index_cfg
  puts "❌ ERROR: #{index_key} configuration not found in algo.yml"
  exit 1
end

# Get instrument
instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)

unless instrument
  puts "❌ Failed to get instrument for #{index_key}"
  exit 1
end

puts "📊 Instrument: #{instrument.symbol_name} (SID: #{instrument.security_id})\n\n"

# Optimize each indicator separately
# IMPORTANT: RSI must be LAST - runs after all other indicators
# Optimization order: ADX → Supertrend → MACD → ATR → RSI
indicators = %i[adx supertrend macd atr rsi]
results = {}

indicators.each do |indicator|
  puts '-' * 80
  puts "Optimizing #{indicator.to_s.upcase} (#{interval}m, #{lookback_days} days)"
  puts '-' * 80

  begin
    start_time = Time.current

    optimizer = Optimization::SingleIndicatorOptimizer.new(
      instrument: instrument,
      interval: interval,
      lookback_days: lookback_days,
      indicator: indicator
    )

    result = optimizer.run

    elapsed = Time.current - start_time

    if result[:error]
      puts "❌ Optimization failed: #{result[:error]}"
      results[indicator] = nil
      next
    end

    unless result[:score] && result[:params] && result[:metrics]
      puts '❌ No valid results returned'
      results[indicator] = nil
      next
    end

    # Display results
    puts "\n✅ Optimization Complete (#{elapsed.round(2)}s)"
    puts "\n📈 Best Parameters:"
    puts "   Average Price Move: #{result[:score].round(4)}%"
    puts "   Total Signals: #{result[:metrics][:total_signals]}"
    puts "   Win Rate: #{(result[:metrics][:win_rate] * 100).round(2)}%"
    puts "   Max Move: #{result[:metrics][:max_move_pct]&.round(4)}%"

    puts "\n⚙️  Parameter Values:"
    result[:params].each do |key, value|
      puts "   #{key}: #{value}"
    end

    results[indicator] = result
  rescue StandardError => e
    puts "❌ ERROR: #{e.class} - #{e.message}"
    puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
    results[indicator] = nil
  end

  puts "\n"
end

# Summary
puts '=' * 80
puts 'OPTIMIZATION SUMMARY'
puts '=' * 80

indicators.each do |indicator|
  if results[indicator]
    result = results[indicator]
    puts "\n📊 #{indicator.to_s.upcase}:"
    puts "   Avg Price Move: #{result[:score]&.round(4)}%"
    puts "   Signals: #{result[:metrics][:total_signals]}"
    puts "   Win Rate: #{(result[:metrics][:win_rate] * 100).round(2)}%" if result[:metrics][:win_rate]
    puts "   Max Move: #{result[:metrics][:max_move_pct]&.round(4)}%" if result[:metrics][:max_move_pct]
    puts "   Best Params: #{result[:params].inspect}"
  else
    puts "\n❌ #{indicator.to_s.upcase}: Optimization failed"
  end
end

puts "\n" + ('=' * 80)
puts '✅ Done! Results saved to best_indicator_params table'
puts '=' * 80
puts "\nTo retrieve optimized parameters:"
puts "  best = BestIndicatorParam.best_for(instrument.id, '#{interval}').first"
puts '  params = best.params'
puts "\n"
