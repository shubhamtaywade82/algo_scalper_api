# frozen_string_literal: true

namespace :trading do
  desc 'Analyze trading day: PnL after each exit, profitable periods, entry/exit conditions'
  task analyze_day: :environment do
    today = Time.zone.today
    puts '=' * 100
    puts "TRADING DAY ANALYSIS: #{today.strftime('%Y-%m-%d')} (Sensex Expiry Day)"
    puts '=' * 100
    puts ''

    # Get all paper positions for today, ordered by exit time (or created_at if not exited)
    all_positions = PositionTracker.paper
                                   .where(created_at: today.beginning_of_day..)
                                   .order(Arel.sql('COALESCE(exited_at, created_at) ASC'))

    exited_positions = all_positions.exited.order(:exited_at)
    active_positions = all_positions.active

    puts '📊 OVERVIEW'
    puts '-' * 100
    puts "Total positions: #{all_positions.count}"
    puts "Exited positions: #{exited_positions.count}"
    puts "Active positions: #{active_positions.count}"
    puts ''

    # Calculate cumulative stats after each exit
    cumulative_realized_pnl = BigDecimal(0)
    cumulative_trades = 0
    winners = 0
    losers = 0
    max_profit = BigDecimal(0)
    max_loss = BigDecimal(0)
    max_drawdown = BigDecimal(0)
    peak_pnl = BigDecimal(0)

    profitable_periods = []
    losing_periods = []

    puts '=' * 100
    puts 'TRADE-BY-TRADE ANALYSIS WITH CUMULATIVE STATS'
    puts '=' * 100
    puts ''

    exited_positions.each_with_index do |position, _idx|
      pnl = position.last_pnl_rupees || BigDecimal(0)
      pnl_pct = (position.last_pnl_pct || 0) * 100.0 # Convert decimal to percentage
      cumulative_realized_pnl += pnl
      cumulative_trades += 1

      if pnl.positive?
        winners += 1
      else
        losers += 1
      end

      # Track peak and drawdown
      peak_pnl = cumulative_realized_pnl if cumulative_realized_pnl > peak_pnl
      drawdown = peak_pnl - cumulative_realized_pnl
      max_drawdown = drawdown if drawdown > max_drawdown

      max_profit = cumulative_realized_pnl if cumulative_realized_pnl > max_profit
      max_loss = cumulative_realized_pnl if cumulative_realized_pnl < max_loss

      # Track profitable/losing periods
      if cumulative_realized_pnl.positive?
        profitable_periods << {
          trade_num: cumulative_trades,
          time: position.exited_at,
          cumulative_pnl: cumulative_realized_pnl,
          pnl_pct: (cumulative_realized_pnl / BigDecimal(100_000)) * 100.0 # Assuming 1L capital
        }
      else
        losing_periods << {
          trade_num: cumulative_trades,
          time: position.exited_at,
          cumulative_pnl: cumulative_realized_pnl,
          pnl_pct: (cumulative_realized_pnl / BigDecimal(100_000)) * 100.0
        }
      end

      win_rate = cumulative_trades.positive? ? (winners.to_f / cumulative_trades * 100.0) : 0.0

      # Display trade details
      puts "[Trade ##{cumulative_trades}] #{position.symbol || 'N/A'}"
      puts "  Entry: #{position.created_at.strftime('%H:%M:%S')} @ ₹#{position.entry_price || 'N/A'}"
      puts "  Exit:  #{position.exited_at&.strftime('%H:%M:%S') || 'N/A'} @ ₹#{position.exit_price || 'N/A'}"
      puts "  Qty: #{position.quantity || 0}"
      puts "  Trade PnL: ₹#{pnl.round(2)} (#{pnl_pct.round(2)}%)"
      puts "  Exit Reason: #{position.exit_reason || 'N/A'}"
      puts ''
      puts '  📈 CUMULATIVE STATS AFTER THIS TRADE:'
      puts "     Realized PnL: ₹#{cumulative_realized_pnl.round(2)}"
      puts "     Total Trades: #{cumulative_trades}"
      puts "     Winners: #{winners} | Losers: #{losers}"
      puts "     Win Rate: #{win_rate.round(2)}%"
      puts "     Peak PnL: ₹#{peak_pnl.round(2)}"
      puts "     Max Drawdown: ₹#{max_drawdown.round(2)}"
      puts ''

      # Show entry/exit conditions from metadata
      meta = position.meta.is_a?(Hash) ? position.meta : {}
      if meta.any?
        puts '  📋 ENTRY CONDITIONS:'
        puts "     Index: #{meta['index_key'] || 'N/A'}"
        puts "     Direction: #{meta['direction'] || 'N/A'}"
        puts "     Strategy: #{meta['entry_strategy'] || 'N/A'}"
        puts "     Entry Path: #{meta['entry_path'] || 'N/A'}"
        puts "     Timeframe: #{meta['entry_timeframe'] || 'N/A'}"
        puts "     Confirmation TF: #{meta['entry_confirmation_timeframe'] || 'N/A'}"
        puts "     Validation Mode: #{meta['entry_validation_mode'] || 'N/A'}"
        puts "     Strategy Mode: #{meta['entry_strategy_mode'] || 'N/A'}"

        # Show any indicator values if present
        indicator_keys = meta.keys.select { |k| k.to_s.match?(/adx|rsi|supertrend|macd|indicator/i) }
        if indicator_keys.any?
          puts '     Indicator Values:'
          indicator_keys.each do |key|
            value = meta[key]
            if value.is_a?(Numeric)
              puts "       #{key}: #{value.round(2)}"
            elsif value.is_a?(Hash)
              puts "       #{key}: #{value.inspect}"
            else
              puts "       #{key}: #{value}"
            end
          end
        end
        puts ''
        puts '  📋 EXIT CONDITIONS:'
        puts "     Exit Path: #{meta['exit_path'] || 'N/A'}"
        puts "     Exit Type: #{meta['exit_type'] || 'N/A'}"
        puts "     Exit Direction: #{meta['exit_direction'] || 'N/A'}"
        puts "     HWM PnL %: #{meta['hwm_pnl_pct'] ? (meta['hwm_pnl_pct'].to_f * 100.0).round(2) : 'N/A'}%"

        # Show all other meta keys for debugging
        other_keys = meta.keys - %w[index_key direction entry_strategy entry_path entry_timeframe
                                    entry_confirmation_timeframe entry_validation_mode entry_strategy_mode
                                    exit_path exit_type exit_direction hwm_pnl_pct exit_reason
                                    exit_triggered_at breakeven_locked trailing_stop_price paper_trading placed_at]
        other_keys -= indicator_keys # Remove indicator keys we already showed
        if other_keys.any?
          puts '     Other Metadata:'
          other_keys.each do |key|
            value = meta[key]
            display_value = if value.is_a?(Hash) || value.is_a?(Array)
                              value.inspect[0..100] # Truncate long values
                            else
                              value.to_s[0..100]
                            end
            puts "       #{key}: #{display_value}"
          end
        end
        puts ''
      end

      puts '-' * 100
      puts ''
    end

    # Final summary
    final_stats = PositionTracker.paper_trading_stats_with_pct(date: today)
    win_rate_final = final_stats[:win_rate] || 0.0

    puts '=' * 100
    puts 'FINAL SUMMARY'
    puts '=' * 100
    puts ''
    puts '📊 Overall Performance:'
    puts "  Total Trades: #{final_stats[:total_trades] || 0}"
    puts "  Winners: #{final_stats[:winners] || 0}"
    puts "  Losers: #{final_stats[:losers] || 0}"
    puts "  Win Rate: #{win_rate_final.round(2)}%"
    puts ''
    puts '💰 PnL Summary:'
    puts "  Realized PnL: ₹#{final_stats[:realized_pnl_rupees] || 0}"
    puts "  Realized PnL %: #{final_stats[:realized_pnl_pct] || 0}%"
    puts "  Unrealized PnL: ₹#{final_stats[:unrealized_pnl_rupees] || 0}"
    puts "  Total PnL: ₹#{final_stats[:total_pnl_rupees] || 0}"
    puts "  Total PnL %: #{final_stats[:total_pnl_pct] || 0}%"
    puts ''
    puts '📈 Peak Performance:'
    puts "  Max Profit Reached: ₹#{max_profit.round(2)}"
    puts "  Max Loss Reached: ₹#{max_loss.round(2)}"
    puts "  Max Drawdown: ₹#{max_drawdown.round(2)}"
    puts ''

    # Profitable periods analysis
    puts '=' * 100
    puts 'PROFITABLE PERIODS'
    puts '=' * 100
    puts ''
    if profitable_periods.any?
      profitable_periods.each do |period|
        puts "  Trade ##{period[:trade_num]} at #{period[:time].strftime('%H:%M:%S')}: ₹#{period[:cumulative_pnl].round(2)} (#{period[:pnl_pct].round(2)}%)"
      end
    else
      puts '  No profitable periods (always in loss)'
    end
    puts ''

    # Losing periods analysis
    puts '=' * 100
    puts 'LOSING PERIODS'
    puts '=' * 100
    puts ''
    if losing_periods.any?
      losing_periods.each do |period|
        puts "  Trade ##{period[:trade_num]} at #{period[:time].strftime('%H:%M:%S')}: ₹#{period[:cumulative_pnl].round(2)} (#{period[:pnl_pct].round(2)}%)"
      end
    else
      puts '  No losing periods (always profitable)'
    end
    puts ''

    # Entry/Exit condition analysis
    puts '=' * 100
    puts 'ENTRY/EXIT CONDITION ANALYSIS'
    puts '=' * 100
    puts ''

    # Group by entry strategy
    entry_strategies = exited_positions.group_by do |p|
      p.meta.is_a?(Hash) ? (p.meta['entry_strategy'] || 'Unknown') : 'Unknown'
    end
    puts '📊 Entry Strategies:'
    entry_strategies.each do |strategy, positions|
      strategy_pnl = positions.sum { |p| p.last_pnl_rupees || 0 }
      strategy_wins = positions.count { |p| (p.last_pnl_rupees || 0).positive? }
      strategy_losses = positions.count { |p| (p.last_pnl_rupees || 0) <= 0 }
      strategy_win_rate = positions.any? ? (strategy_wins.to_f / positions.count * 100.0) : 0.0
      puts "  #{strategy}:"
      puts "    Trades: #{positions.count}"
      puts "    PnL: ₹#{strategy_pnl.round(2)}"
      puts "    Win Rate: #{strategy_win_rate.round(2)}% (#{strategy_wins}W/#{strategy_losses}L)"
    end
    puts ''

    # Group by exit reason
    exit_reasons = exited_positions.group_by { |p| p.exit_reason || 'Unknown' }
    puts '📊 Exit Reasons:'
    exit_reasons.each do |reason, positions|
      reason_pnl = positions.sum { |p| p.last_pnl_rupees || 0 }
      reason_wins = positions.count { |p| (p.last_pnl_rupees || 0).positive? }
      reason_losses = positions.count { |p| (p.last_pnl_rupees || 0) <= 0 }
      reason_win_rate = positions.any? ? (reason_wins.to_f / positions.count * 100.0) : 0.0
      puts "  #{reason}:"
      puts "    Trades: #{positions.count}"
      puts "    PnL: ₹#{reason_pnl.round(2)}"
      puts "    Win Rate: #{reason_win_rate.round(2)}% (#{reason_wins}W/#{reason_losses}L)"
    end
    puts ''

    # Group by index
    index_groups = exited_positions.group_by { |p| p.meta.is_a?(Hash) ? (p.meta['index_key'] || 'Unknown') : 'Unknown' }
    puts '📊 Performance by Index:'
    index_groups.each do |index, positions|
      index_pnl = positions.sum { |p| p.last_pnl_rupees || 0 }
      index_wins = positions.count { |p| (p.last_pnl_rupees || 0).positive? }
      index_losses = positions.count { |p| (p.last_pnl_rupees || 0) <= 0 }
      index_win_rate = positions.any? ? (index_wins.to_f / positions.count * 100.0) : 0.0
      puts "  #{index}:"
      puts "    Trades: #{positions.count}"
      puts "    PnL: ₹#{index_pnl.round(2)}"
      puts "    Win Rate: #{index_win_rate.round(2)}% (#{index_wins}W/#{index_losses}L)"
    end
    puts ''

    # Time-based analysis
    puts '=' * 100
    puts 'TIME-BASED ANALYSIS'
    puts '=' * 100
    puts ''

    # Group by hour
    hourly_groups = exited_positions.group_by { |p| p.exited_at&.hour || p.created_at.hour }
    puts '📊 Performance by Hour (Exit Time):'
    hourly_groups.sort.each do |hour, positions|
      hour_pnl = positions.sum { |p| p.last_pnl_rupees || 0 }
      hour_wins = positions.count { |p| (p.last_pnl_rupees || 0).positive? }
      hour_losses = positions.count { |p| (p.last_pnl_rupees || 0) <= 0 }
      hour_win_rate = positions.any? ? (hour_wins.to_f / positions.count * 100.0) : 0.0
      puts "  #{hour}:00 - #{hour + 1}:00:"
      puts "    Trades: #{positions.count}"
      puts "    PnL: ₹#{hour_pnl.round(2)}"
      puts "    Win Rate: #{hour_win_rate.round(2)}% (#{hour_wins}W/#{hour_losses}L)"
    end
    puts ''

    puts '=' * 100
    puts 'ANALYSIS COMPLETE'
    puts '=' * 100
  end
end
