# frozen_string_literal: true

# Script to analyze PositionTracker profitability by trading session time periods
# Identifies which periods within the 6.5 hour trading session (9:15 AM - 3:30 PM IST)
# were profitable for supertrend + ADX strategy
# Usage: rails runner scripts/analyze_positions_by_time_intervals.rb [interval_minutes]
# Default interval: 30 minutes

interval_minutes = (ARGV[0]&.to_i || 30).clamp(15, 60)
interval_seconds = interval_minutes * 60

puts "\n#{'=' * 100}"
puts 'TRADING SESSION PROFITABILITY ANALYSIS (Supertrend + ADX Strategy)'
puts 'Trading Hours: 9:15 AM - 3:30 PM IST (6.5 hours)'
puts "Analysis Interval: #{interval_minutes} minutes"
puts "#{'=' * 100}\n"

# Get all paper trading positions
all_trackers = PositionTracker.paper.order(created_at: :asc)
exited_trackers = PositionTracker.paper.exited.order(created_at: :asc)
active_trackers = PositionTracker.paper.active.order(created_at: :asc)

# Filter to trading hours only (9:15 AM - 3:30 PM IST)
def within_trading_hours?(time)
  return false unless time

  hour = time.hour
  minute = time.min

  # Market hours: 9:15 AM to 3:30 PM IST
  market_open = hour > 9 || (hour == 9 && minute >= 15)
  market_close = hour > 15 || (hour == 15 && minute >= 30)

  market_open && !market_close
end

# Filter positions to trading hours only
trading_hour_trackers = all_trackers.select { |t| within_trading_hours?(t.created_at) }
trading_hour_exited = exited_trackers.select { |t| within_trading_hours?(t.created_at) }
trading_hour_active = active_trackers.select { |t| within_trading_hours?(t.created_at) }

puts '📊 OVERVIEW'
puts '-' * 100
puts "Total Positions (All): #{all_trackers.count}"
puts "  - Exited: #{exited_trackers.count}"
puts "  - Active: #{active_trackers.count}"
puts ''
puts "Positions During Trading Hours (9:15 AM - 3:30 PM): #{trading_hour_trackers.count}"
puts "  - Exited: #{trading_hour_exited.count}"
puts "  - Active: #{trading_hour_active.count}"
puts ''

# Group positions by time intervals within trading hours
def group_by_trading_interval(trackers, interval_seconds)
  grouped = {}

  trackers.each do |tracker|
    entry_time = tracker.created_at
    next unless entry_time

    # Round down to nearest interval, but align to trading session boundaries
    interval_start = Time.zone.at((entry_time.to_i / interval_seconds) * interval_seconds)

    # Format as HH:MM for display (focus on time, not date)
    hour = interval_start.hour
    minute = interval_start.min
    interval_key = format('%02d:%02d', hour, minute)

    # Create a unique key per day + time for grouping
    date_key = interval_start.strftime('%Y-%m-%d')
    full_key = "#{date_key} #{interval_key}"

    grouped[full_key] ||= {
      start_time: interval_start,
      time_only: interval_key,
      date: date_key,
      positions: [],
      exited_positions: [],
      active_positions: []
    }

    grouped[full_key][:positions] << tracker
    grouped[full_key][:exited_positions] << tracker if tracker.exited?
    grouped[full_key][:active_positions] << tracker if tracker.active?
  end

  grouped
end

interval_groups = group_by_trading_interval(trading_hour_trackers, interval_seconds)

# Calculate metrics for each interval
interval_metrics = interval_groups.map do |interval_key, data|
  exited = data[:exited_positions]
  active = data[:active_positions]

  # Realized PnL from exited positions
  realized_pnl = exited.sum { |t| t.last_pnl_rupees.to_f }

  # Unrealized PnL from active positions
  unrealized_pnl = active.sum { |t| t.current_pnl_rupees.to_f }

  total_pnl = realized_pnl + unrealized_pnl

  # Win rate (only for exited positions)
  winners = exited.count { |t| (t.last_pnl_rupees || 0).positive? }
  losers = exited.count { |t| (t.last_pnl_rupees || 0).negative? }
  win_rate = exited.any? ? (winners.to_f / exited.count * 100.0) : 0.0

  # Average PnL per trade
  avg_pnl = exited.any? ? (realized_pnl / exited.count) : 0.0

  # Profitability classification
  profitability = if total_pnl.positive?
                    '✅ PROFITABLE'
                  elsif total_pnl.negative?
                    '❌ UNPROFITABLE'
                  else
                    '➖ BREAKEVEN'
                  end

  {
    interval_key: interval_key,
    time_only: data[:time_only],
    start_time: data[:start_time],
    total_trades: data[:positions].count,
    exited_trades: exited.count,
    active_trades: active.count,
    winners: winners,
    losers: losers,
    win_rate: win_rate,
    realized_pnl: realized_pnl,
    unrealized_pnl: unrealized_pnl,
    total_pnl: total_pnl,
    avg_pnl: avg_pnl,
    profitability: profitability
  }
end.sort_by { |m| m[:start_time] }

# Aggregate by time of day (across all days) to see which time periods are consistently profitable
time_period_metrics = interval_metrics.group_by { |m| m[:time_only] }.map do |time_key, intervals|
  total_trades = intervals.sum { |m| m[:total_trades] }
  total_pnl = intervals.sum { |m| m[:total_pnl] }
  total_winners = intervals.sum { |m| m[:winners] }
  total_losers = intervals.sum { |m| m[:losers] }
  exited_trades = intervals.sum { |m| m[:exited_trades] }
  win_rate = exited_trades.positive? ? (total_winners.to_f / exited_trades * 100.0) : 0.0
  avg_pnl_per_trade = exited_trades.positive? ? (total_pnl / exited_trades) : 0.0
  interval_count = intervals.count

  {
    time_key: time_key,
    interval_count: interval_count,
    total_trades: total_trades,
    exited_trades: exited_trades,
    winners: total_winners,
    losers: total_losers,
    win_rate: win_rate,
    total_pnl: total_pnl,
    avg_pnl_per_trade: avg_pnl_per_trade,
    profitability: if total_pnl.positive?
                     '✅ PROFITABLE'
                   else
                     (total_pnl.negative? ? '❌ UNPROFITABLE' : '➖ BREAKEVEN')
                   end
  }
end.sort_by { |m| m[:time_key] }

# Display results - Focus on trading session time periods
puts '⏰ TRADING SESSION TIME PERIOD ANALYSIS'
puts 'Shows profitability by time period across all trading days'
puts '-' * 100
puts 'Time       | Days     | Trades | Exited | Win%     | Total PnL ₹  | Avg PnL/Trade ₹ | Status         '
puts '-' * 100

time_period_metrics.each do |metrics|
  metrics[:exited_trades].positive? ? "#{metrics[:winners]}/#{metrics[:losers]}" : 'N/A'

  puts format('%-10s | %-8d | %-6d | %-6d | %-8.1f | %-12.2f | %-15.2f | %-15s',
              metrics[:time_key],
              metrics[:interval_count],
              metrics[:total_trades],
              metrics[:exited_trades],
              metrics[:win_rate],
              metrics[:total_pnl],
              metrics[:avg_pnl_per_trade],
              metrics[:profitability])
end

puts '-' * 100
puts ''

# Summary statistics for time periods
profitable_periods = time_period_metrics.select { |m| m[:total_pnl].positive? }
unprofitable_periods = time_period_metrics.select { |m| m[:total_pnl].negative? }
breakeven_periods = time_period_metrics.select { |m| m[:total_pnl].zero? }

puts '📈 SUMMARY STATISTICS (Trading Session Time Periods)'
puts '-' * 100
puts "Total Time Periods Analyzed: #{time_period_metrics.count}"
puts "  ✅ Profitable Periods: #{profitable_periods.count} (#{(profitable_periods.count.to_f / time_period_metrics.count * 100).round(1)}%)"
puts "  ❌ Unprofitable Periods: #{unprofitable_periods.count} (#{(unprofitable_periods.count.to_f / time_period_metrics.count * 100).round(1)}%)"
puts "  ➖ Breakeven Periods: #{breakeven_periods.count} (#{(breakeven_periods.count.to_f / time_period_metrics.count * 100).round(1)}%)"
puts ''

if profitable_periods.any?
  profitable_pnl = profitable_periods.sum { |m| m[:total_pnl] }
  profitable_trades = profitable_periods.sum { |m| m[:total_trades] }

  puts '✅ PROFITABLE TIME PERIODS (Supertrend + ADX Strategy)'
  puts '-' * 100
  puts "Total Profit: ₹#{profitable_pnl.round(2)}"
  puts "Total Trades: #{profitable_trades}"
  puts ''

  puts 'Most Profitable Time Periods (Ranked by Total PnL):'
  profitable_periods.sort_by { |m| -m[:total_pnl] }.each_with_index do |metrics, idx|
    puts "  #{idx + 1}. #{metrics[:time_key]} | " \
         "PnL: ₹#{metrics[:total_pnl].round(2)} | " \
         "Trades: #{metrics[:total_trades]} | " \
         "Win Rate: #{metrics[:win_rate].round(1)}% | " \
         "Avg PnL/Trade: ₹#{metrics[:avg_pnl_per_trade].round(2)} | " \
         "Days: #{metrics[:interval_count]}"
  end
  puts ''
end

if unprofitable_periods.any?
  unprofitable_pnl = unprofitable_periods.sum { |m| m[:total_pnl] }
  unprofitable_trades = unprofitable_periods.sum { |m| m[:total_trades] }

  puts '❌ UNPROFITABLE TIME PERIODS (Supertrend + ADX Strategy)'
  puts '-' * 100
  puts "Total Loss: ₹#{unprofitable_pnl.round(2)}"
  puts "Total Trades: #{unprofitable_trades}"
  puts ''

  puts 'Worst Time Periods (Ranked by Total Loss):'
  unprofitable_periods.sort_by { |m| m[:total_pnl] }.each_with_index do |metrics, idx|
    puts "  #{idx + 1}. #{metrics[:time_key]} | " \
         "PnL: ₹#{metrics[:total_pnl].round(2)} | " \
         "Trades: #{metrics[:total_trades]} | " \
         "Win Rate: #{metrics[:win_rate].round(1)}% | " \
         "Avg PnL/Trade: ₹#{metrics[:avg_pnl_per_trade].round(2)} | " \
         "Days: #{metrics[:interval_count]}"
  end
  puts ''
end

# Hourly analysis (aggregate by hour across all days)
puts '🕐 HOURLY ANALYSIS (Across All Trading Days)'
puts '-' * 100
hourly_groups = time_period_metrics.group_by { |m| m[:time_key].split(':').first.to_i }

hourly_metrics = hourly_groups.map do |hour, periods|
  total_trades = periods.sum { |m| m[:total_trades] }
  total_pnl = periods.sum { |m| m[:total_pnl] }
  total_winners = periods.sum { |m| m[:winners] }
  total_losers = periods.sum { |m| m[:losers] }
  exited_trades = periods.sum { |m| m[:exited_trades] }
  win_rate = exited_trades.positive? ? (total_winners.to_f / exited_trades * 100.0) : 0.0
  avg_pnl_per_trade = exited_trades.positive? ? (total_pnl / exited_trades) : 0.0

  {
    hour: hour,
    hour_label: format('%02d:00-%02d:59', hour, hour),
    periods_count: periods.count,
    total_trades: total_trades,
    exited_trades: exited_trades,
    winners: total_winners,
    losers: total_losers,
    win_rate: win_rate,
    total_pnl: total_pnl,
    avg_pnl_per_trade: avg_pnl_per_trade,
    profitability: if total_pnl.positive?
                     '✅ PROFITABLE'
                   else
                     (total_pnl.negative? ? '❌ UNPROFITABLE' : '➖ BREAKEVEN')
                   end
  }
end.sort_by { |m| m[:hour] }

puts 'Hour            | Periods  | Trades | Exited | Win%     | Total PnL ₹  | Avg PnL/Trade ₹ | Status         '
puts '-' * 100

hourly_metrics.each do |metrics|
  puts format('%-15s | %-8d | %-6d | %-6d | %-8.1f | %-12.2f | %-15.2f | %-15s',
              metrics[:hour_label],
              metrics[:periods_count],
              metrics[:total_trades],
              metrics[:exited_trades],
              metrics[:win_rate],
              metrics[:total_pnl],
              metrics[:avg_pnl_per_trade],
              metrics[:profitability])
end

puts '-' * 100
puts ''

# Identify best and worst hours
profitable_hours = hourly_metrics.select { |m| m[:total_pnl].positive? }
unprofitable_hours = hourly_metrics.select { |m| m[:total_pnl].negative? }

if profitable_hours.any?
  puts '✅ BEST TRADING HOURS (Supertrend + ADX Strategy)'
  puts '-' * 100
  profitable_hours.sort_by { |m| -m[:total_pnl] }.each_with_index do |metrics, idx|
    puts "  #{idx + 1}. #{metrics[:hour_label]} | " \
         "PnL: ₹#{metrics[:total_pnl].round(2)} | " \
         "Trades: #{metrics[:total_trades]} | " \
         "Win Rate: #{metrics[:win_rate].round(1)}% | " \
         "Avg PnL/Trade: ₹#{metrics[:avg_pnl_per_trade].round(2)}"
  end
  puts ''
end

if unprofitable_hours.any?
  puts '❌ WORST TRADING HOURS (Supertrend + ADX Strategy)'
  puts '-' * 100
  unprofitable_hours.sort_by { |m| m[:total_pnl] }.each_with_index do |metrics, idx|
    puts "  #{idx + 1}. #{metrics[:hour_label]} | " \
         "PnL: ₹#{metrics[:total_pnl].round(2)} | " \
         "Trades: #{metrics[:total_trades]} | " \
         "Win Rate: #{metrics[:win_rate].round(1)}% | " \
         "Avg PnL/Trade: ₹#{metrics[:avg_pnl_per_trade].round(2)}"
  end
  puts ''
end

# Time range analysis (market open, mid-day, close)
puts '📊 MARKET SESSION ANALYSIS'
puts '-' * 100

def classify_session_period(time_key)
  hour = time_key.split(':').first.to_i
  minute = time_key.split(':').last.to_i

  case hour
  when 9
    'Market Open (9:15-9:59)'
  when 10, 11
    'Morning Session (10:00-11:59)'
  when 12, 13
    'Mid-Day (12:00-13:59)'
  when 14
    'Afternoon (14:00-14:59)'
  when 15
    minute < 30 ? 'Market Close (15:00-15:29)' : 'Market Close (15:30)'
  else
    'Other'
  end
end

session_groups = time_period_metrics.group_by { |m| classify_session_period(m[:time_key]) }

session_metrics = session_groups.map do |session_name, periods|
  total_trades = periods.sum { |m| m[:total_trades] }
  total_pnl = periods.sum { |m| m[:total_pnl] }
  total_winners = periods.sum { |m| m[:winners] }
  total_losers = periods.sum { |m| m[:losers] }
  exited_trades = periods.sum { |m| m[:exited_trades] }
  win_rate = exited_trades.positive? ? (total_winners.to_f / exited_trades * 100.0) : 0.0

  {
    session_name: session_name,
    periods_count: periods.count,
    total_trades: total_trades,
    exited_trades: exited_trades,
    winners: total_winners,
    losers: total_losers,
    win_rate: win_rate,
    total_pnl: total_pnl,
    avg_pnl_per_trade: exited_trades.positive? ? (total_pnl / exited_trades) : 0.0
  }
end.sort_by { |m| -m[:total_pnl] }

puts 'Session                        | Periods  | Trades | Exited | Win%     | Total PnL ₹  | Avg PnL/Trade ₹'
puts '-' * 100

session_metrics.each do |metrics|
  puts format('%-30s | %-8d | %-6d | %-6d | %-8.1f | %-12.2f | %-15.2f',
              metrics[:session_name],
              metrics[:periods_count],
              metrics[:total_trades],
              metrics[:exited_trades],
              metrics[:win_rate],
              metrics[:total_pnl],
              metrics[:avg_pnl_per_trade])
end

puts '-' * 100
puts ''

# Recommendations
puts '💡 RECOMMENDATIONS FOR SUPERTREND + ADX STRATEGY'
puts '-' * 100

best_session = session_metrics.max_by { |m| m[:total_pnl] }
worst_session = session_metrics.min_by { |m| m[:total_pnl] }

if best_session && best_session[:total_pnl].positive?
  puts "✅ BEST SESSION: #{best_session[:session_name]}"
  puts "   - Total PnL: ₹#{best_session[:total_pnl].round(2)}"
  puts "   - Win Rate: #{best_session[:win_rate].round(1)}%"
  puts "   - Average PnL per Trade: ₹#{best_session[:avg_pnl_per_trade].round(2)}"
  puts '   → Consider focusing trading during this session'
  puts ''
end

if worst_session && worst_session[:total_pnl].negative?
  puts "❌ WORST SESSION: #{worst_session[:session_name]}"
  puts "   - Total PnL: ₹#{worst_session[:total_pnl].round(2)}"
  puts "   - Win Rate: #{worst_session[:win_rate].round(1)}%"
  puts "   - Average PnL per Trade: ₹#{worst_session[:avg_pnl_per_trade].round(2)}"
  puts '   → Consider avoiding or reducing exposure during this session'
  puts ''
end

# High probability time windows
high_prob_periods = time_period_metrics.select do |m|
  m[:exited_trades] >= 3 && m[:win_rate] >= 70.0 && m[:total_pnl].positive?
end

if high_prob_periods.any?
  puts '🎯 HIGH PROBABILITY TIME PERIODS (≥70% Win Rate, ≥3 Trades, Profitable)'
  puts 'These are the time periods where Supertrend + ADX strategy works with high probability'
  puts '-' * 100
  high_prob_periods.sort_by { |m| -m[:win_rate] }.each do |metrics|
    puts "  • #{metrics[:time_key]} | " \
         "Win Rate: #{metrics[:win_rate].round(1)}% | " \
         "Trades: #{metrics[:total_trades]} | " \
         "PnL: ₹#{metrics[:total_pnl].round(2)} | " \
         "Avg PnL/Trade: ₹#{metrics[:avg_pnl_per_trade].round(2)} | " \
         "W/L: #{metrics[:winners]}/#{metrics[:losers]} | " \
         "Days: #{metrics[:interval_count]}"
  end
  puts ''
end

# Final recommendations
puts '💡 KEY INSIGHTS FOR SUPERTREND + ADX STRATEGY'
puts '-' * 100

if profitable_periods.any?
  best_period = profitable_periods.max_by { |m| m[:total_pnl] }
  best_win_rate_period = profitable_periods.max_by { |m| m[:win_rate] }

  puts '✅ OPTIMAL TRADING PERIODS:'
  puts "   Best Profit Period: #{best_period[:time_key]} (₹#{best_period[:total_pnl].round(2)})"
  puts "   Best Win Rate Period: #{best_win_rate_period[:time_key]} (#{best_win_rate_period[:win_rate].round(1)}% win rate)"
  puts ''
end

if unprofitable_periods.any?
  worst_period = unprofitable_periods.min_by { |m| m[:total_pnl] }
  puts '❌ AVOID THESE PERIODS:'
  puts "   Worst Period: #{worst_period[:time_key]} (₹#{worst_period[:total_pnl].round(2)} loss)"
  puts ''
end

puts '📋 RECOMMENDATION:'
puts '   Focus trading during profitable time periods identified above.'
puts '   Consider reducing or avoiding positions during unprofitable periods.'
puts ''

puts '=' * 100
puts 'ANALYSIS COMPLETE'
puts "#{'=' * 100}\n"
