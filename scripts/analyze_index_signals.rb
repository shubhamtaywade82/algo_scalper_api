# frozen_string_literal: true

# Script to analyze why only BANKNIFTY positions were created
# Usage: rails runner scripts/analyze_index_signals.rb

puts "\n#{'=' * 100}"
puts 'INDEX SIGNAL ANALYSIS - Why Only BANKNIFTY?'
puts "#{'=' * 100}\n"

indices = AlgoConfig.fetch[:indices] || []

indices.each do |index_cfg|
  puts "📊 Analyzing #{index_cfg[:key]}"
  puts '-' * 100

  # Get instrument
  instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
  unless instrument
    puts '  ❌ Instrument not found'
    puts ''
    next
  end

  puts "  ✅ Instrument found: #{instrument.symbol_name}"

  # Analyze signal (stock Supertrend path)
  begin
    signals_cfg = AlgoConfig.fetch[:signals] || {}
    primary_tf = signals_cfg[:primary_timeframe] || '1m'
    result = Signal::Engine.send(:execute_supertrend_only_flow, index_cfg, instrument, signals_cfg, primary_tf)

    if result
      puts '  ✅ Supertrend analysis successful'
      puts "  Direction: #{result[:direction]}"
      adx = result.dig(:primary_analysis, :adx_value)
      trend = result.dig(:primary_analysis, :supertrend, :trend)
      puts "  ADX: #{adx&.round(2) || 'N/A'} | Supertrend: #{trend || 'N/A'}"

      positions = PositionTracker.paper.where("meta->>'index_key' = ?", index_cfg[:key])
      puts "  Current positions: #{positions.count} (Active: #{positions.active.count}, Exited: #{positions.exited.count})"
    else
      puts '  ⚠️  No trade signal (Supertrend :none or analysis blocked)'
    end
  rescue StandardError => e
    puts "  ❌ Error during analysis: #{e.class} - #{e.message}"
    puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
  end

  puts ''
end

# Check daily limits
puts '📊 DAILY LIMITS CHECK'
puts '-' * 100
daily_limits = Live::DailyLimits.new

indices.each do |index_cfg|
  check = daily_limits.can_trade?(index_key: index_cfg[:key])
  puts "#{index_cfg[:key]}:"
  puts "  Allowed: #{check[:allowed]}"
  puts "  Reason: #{check[:reason] || 'N/A'}"
  puts "  Daily Loss: ₹#{check[:daily_loss]&.round(2) || 0}"
  puts "  Daily Trades: #{check[:daily_trades] || 0}"
  puts ''
end

# Check trade limits from config
puts '📊 TRADE LIMITS FROM CONFIG'
puts '-' * 100
indices.each do |index_cfg|
  max_trades = index_cfg.dig(:trade_limits, :max_trades_per_day)
  puts "#{index_cfg[:key]}: max_trades_per_day = #{max_trades || 'N/A'}"
end

puts "#{'=' * 100}\n"
