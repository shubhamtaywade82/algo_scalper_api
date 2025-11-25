# frozen_string_literal: true

# Script to analyze why only BANKNIFTY positions were created
# Usage: rails runner scripts/analyze_index_signals.rb

puts "\n" + "=" * 100
puts "INDEX SIGNAL ANALYSIS - Why Only BANKNIFTY?"
puts "=" * 100 + "\n"

indices = AlgoConfig.fetch[:indices] || []

indices.each do |index_cfg|
  puts "📊 Analyzing #{index_cfg[:key]}"
  puts "-" * 100

  # Get instrument
  instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
  unless instrument
    puts "  ❌ Instrument not found"
    puts ""
    next
  end

  puts "  ✅ Instrument found: #{instrument.symbol_name}"

  # Analyze signal
  begin
    result = Signal::Engine.analyze_multi_timeframe(index_cfg: index_cfg, instrument: instrument)

    if result[:status] == :ok
      puts "  ✅ Signal analysis successful"
      puts "  Primary Direction: #{result[:primary_direction]}"
      puts "  Confirmation Direction: #{result[:confirmation_direction] || 'N/A'}"
      puts "  Final Direction: #{result[:final_direction]}"

      if result[:final_direction] == :avoid
        puts "  ⚠️  FINAL DIRECTION IS :avoid - This is why no positions were created!"

        # Check why it's avoid
        primary = result.dig(:timeframe_results, :primary)
        confirmation = result.dig(:timeframe_results, :confirmation)

        if primary
          puts "  Primary Timeframe Analysis:"
          puts "    Direction: #{primary[:direction]}"
          puts "    ADX Value: #{primary[:adx_value]&.round(2) || 'N/A'}"
          puts "    Supertrend: #{primary.dig(:supertrend, :trend) || 'N/A'}"

          if primary[:direction] == :avoid
            puts "    ⚠️  Primary timeframe returned :avoid"
          end
        end

        if confirmation
          puts "  Confirmation Timeframe Analysis:"
          puts "    Direction: #{confirmation[:direction]}"
          puts "    ADX Value: #{confirmation[:adx_value]&.round(2) || 'N/A'}"
          puts "    Supertrend: #{confirmation.dig(:supertrend, :trend) || 'N/A'}"

          if confirmation[:direction] == :avoid
            puts "    ⚠️  Confirmation timeframe returned :avoid"
          end
        end

        # Check if directions mismatch
        if primary && confirmation && primary[:direction] != confirmation[:direction] &&
           primary[:direction] != :avoid && confirmation[:direction] != :avoid
          puts "  ⚠️  Directions mismatch: Primary=#{primary[:direction]}, Confirmation=#{confirmation[:direction]}"
        end
      else
        puts "  ✅ Final direction is #{result[:final_direction]} - Should create positions"

        # Check if there are any positions
        positions = PositionTracker.paper.where("meta->>'index_key' = ?", index_cfg[:key])
        puts "  Current positions: #{positions.count} (Active: #{positions.active.count}, Exited: #{positions.exited.count})"
      end
    else
      puts "  ❌ Signal analysis failed: #{result[:message]}"
    end
  rescue StandardError => e
    puts "  ❌ Error during analysis: #{e.class} - #{e.message}"
    puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
  end

  puts ""
end

# Check daily limits
puts "📊 DAILY LIMITS CHECK"
puts "-" * 100
daily_limits = Live::DailyLimits.new

indices.each do |index_cfg|
  check = daily_limits.can_trade?(index_key: index_cfg[:key])
  puts "#{index_cfg[:key]}:"
  puts "  Allowed: #{check[:allowed]}"
  puts "  Reason: #{check[:reason] || 'N/A'}"
  puts "  Daily Loss: ₹#{check[:daily_loss]&.round(2) || 0}"
  puts "  Daily Trades: #{check[:daily_trades] || 0}"
  puts ""
end

# Check trade limits from config
puts "📊 TRADE LIMITS FROM CONFIG"
puts "-" * 100
indices.each do |index_cfg|
  max_trades = index_cfg.dig(:trade_limits, :max_trades_per_day)
  puts "#{index_cfg[:key]}: max_trades_per_day = #{max_trades || 'N/A'}"
end

puts "=" * 100 + "\n"

