# frozen_string_literal: true

# Script to run parameter optimization for NIFTY and SENSEX
# Usage: rails runner scripts/optimize_nifty_sensex.rb [interval] [lookback_days]
#
# Examples:
#   rails runner scripts/optimize_nifty_sensex.rb 5 45    # 5m interval, 45 days
#   rails runner scripts/optimize_nifty_sensex.rb 1 30    # 1m interval, 30 days
#   rails runner scripts/optimize_nifty_sensex.rb 15 90   # 15m interval, 90 days

# Check if table exists
unless BestIndicatorParam.table_exists?
  puts "\n❌ ERROR: best_indicator_params table does not exist!"
  puts "\nPlease run the migration first:"
  puts '  rails db:migrate'
  puts "\nOr create the table manually:"
  puts '  rails db:migrate:status'
  puts '  rails db:migrate'
  exit 1
end

# Parse arguments
interval = ARGV[0] || '5'
lookback_days = (ARGV[1] || '45').to_i
test_mode = ['test', '--test'].include?(ARGV[2])

puts "\n#{'=' * 80}"
puts 'Indicator Parameter Optimization - NIFTY & SENSEX'
puts '=' * 80
puts "Interval: #{interval}m"
puts "Lookback: #{lookback_days} days"
puts "#{'=' * 80}\n"

# Get index configurations
algo_config = AlgoConfig.fetch
nifty_cfg = algo_config[:indices]&.find { |i| i[:key] == 'NIFTY' }
sensex_cfg = algo_config[:indices]&.find { |i| i[:key] == 'SENSEX' }

unless nifty_cfg
  puts '❌ ERROR: NIFTY configuration not found in algo.yml'
  exit 1
end

unless sensex_cfg
  puts '❌ ERROR: SENSEX configuration not found in algo.yml'
  puts '   Note: SENSEX may not be configured. Continuing with NIFTY only...'
end

# Helper to run optimization
def run_optimization(index_name, index_cfg, interval, lookback_days, test_mode = false)
  puts "\n#{'-' * 80}"
  puts "Optimizing #{index_name} (#{interval}m, #{lookback_days} days)"
  puts '-' * 80

  begin
    # Get instrument
    instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)

    unless instrument
      puts "❌ Failed to get instrument for #{index_name}"
      return nil
    end

    puts "📊 Instrument: #{instrument.symbol_name} (SID: #{instrument.security_id})"
    puts '🔄 Starting optimization...'
    $stdout.flush

    # Test data fetch first
    puts '   Testing data fetch...'
    $stdout.flush
    test_data = instrument.intraday_ohlc(interval: interval, days: lookback_days)
    if test_data.blank?
      puts '   ❌ No data returned from API'
      return nil
    end
    puts "   ✅ Data fetch successful (#{test_data.is_a?(Hash) ? test_data.keys.size : test_data.size} records)"
    $stdout.flush

    start_time = Time.current

    # Run optimization
    puts '   Creating optimizer...'
    $stdout.flush
    optimizer = Optimization::IndicatorOptimizer.new(
      instrument: instrument,
      interval: interval,
      lookback_days: lookback_days,
      test_mode: test_mode
    )
    if test_mode
      puts '   ⚠️  TEST MODE: Using reduced parameter space for faster testing'
      $stdout.flush
    end
    puts '   Running optimization (this may take several minutes)...'
    $stdout.flush

    result = optimizer.run

    elapsed = Time.current - start_time

    if result[:error]
      puts "❌ Optimization failed: #{result[:error]}"
      return nil
    end

    unless result[:score] && result[:params] && result[:metrics]
      puts '❌ No valid results returned'
      return nil
    end

    # Display results
    puts "\n✅ Optimization Complete (#{elapsed.round(2)}s)"
    puts "\n📈 Best Parameters:"
    puts "   Sharpe Ratio: #{result[:score].round(4)}"
    puts "   Win Rate: #{(result[:metrics][:win_rate] * 100).round(2)}%"
    puts "   Expectancy: #{result[:metrics][:expectancy].round(4)}"
    puts "   Net PnL: #{result[:metrics][:net_pnl].round(2)}"
    puts "   Avg Move: #{result[:metrics][:avg_move].round(4)}%"

    puts "\n⚙️  Parameter Values:"
    result[:params].each do |key, value|
      puts "   #{key}: #{value}"
    end

    # Check if saved to database
    best = BestIndicatorParam.best_for(instrument.id, interval).first
    if best
      puts "\n💾 Saved to database:"
      puts "   Score: #{best.score.round(4)}"
      puts "   Updated: #{best.updated_at}"
    end

    result
  rescue StandardError => e
    puts "❌ ERROR: #{e.class} - #{e.message}"
    puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
    nil
  end
end

# Run optimizations
results = {}

# Optimize NIFTY
results[:nifty] = run_optimization('NIFTY', nifty_cfg, interval, lookback_days, test_mode) if nifty_cfg

# Optimize SENSEX
results[:sensex] = run_optimization('SENSEX', sensex_cfg, interval, lookback_days, test_mode) if sensex_cfg

# Summary
puts "\n#{'=' * 80}"
puts 'OPTIMIZATION SUMMARY'
puts '=' * 80

if results[:nifty]
  puts "\n📊 NIFTY (#{interval}m):"
  puts "   Sharpe: #{results[:nifty][:score]&.round(4)}"
  puts "   Win Rate: #{(results[:nifty][:metrics][:win_rate] * 100).round(2)}%"
  puts "   ADX Threshold: #{results[:nifty][:params][:adx_thresh]}"
  puts "   RSI Lo/Hi: #{results[:nifty][:params][:rsi_lo]}/#{results[:nifty][:params][:rsi_hi]}"
else
  puts "\n❌ NIFTY: Optimization failed"
end

if results[:sensex]
  puts "\n📊 SENSEX (#{interval}m):"
  puts "   Sharpe: #{results[:sensex][:score]&.round(4)}"
  puts "   Win Rate: #{(results[:sensex][:metrics][:win_rate] * 100).round(2)}%"
  puts "   ADX Threshold: #{results[:sensex][:params][:adx_thresh]}"
  puts "   RSI Lo/Hi: #{results[:sensex][:params][:rsi_lo]}/#{results[:sensex][:params][:rsi_hi]}"
else
  puts "\n❌ SENSEX: Optimization failed or not configured"
end

puts "\n#{'=' * 80}"
puts '✅ Done! Results saved to best_indicator_params table'
puts '=' * 80
puts "\nTo retrieve optimized parameters:"
puts "  best = BestIndicatorParam.best_for(instrument.id, '#{interval}').first"
puts '  params = best.params'
puts "\n"
