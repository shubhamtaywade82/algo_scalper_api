# frozen_string_literal: true

# Script to analyze PositionTracker PnL decline
# Usage: rails runner scripts/analyze_pnl_decline.rb

puts "\n#{'=' * 80}"
puts 'PNL DECLINE ANALYSIS'
puts "#{'=' * 80}\n"

# Get all paper trading positions
all_trackers = PositionTracker.paper.order(created_at: :asc)
exited_trackers = PositionTracker.paper.exited.order(created_at: :asc)
active_trackers = PositionTracker.paper.active.order(created_at: :asc)

puts '📊 OVERVIEW'
puts '-' * 80
puts "Total Positions: #{all_trackers.count}"
puts "  - Exited: #{exited_trackers.count}"
puts "  - Active: #{active_trackers.count}"
puts ''

# Calculate cumulative PnL over time
puts '📈 CUMULATIVE PNL PROGRESSION'
puts '-' * 80
cumulative_pnl = 0.0
peak_pnl = 0.0
peak_time = nil
max_drawdown = 0.0
max_drawdown_time = nil

pnl_timeline = []

all_trackers.each do |tracker|
  pnl = tracker.last_pnl_rupees.to_f
  cumulative_pnl += pnl if tracker.exited?

  # For active positions, use current PnL
  cumulative_pnl += pnl if tracker.active?

  if cumulative_pnl > peak_pnl
    peak_pnl = cumulative_pnl
    peak_time = tracker.updated_at
  end

  drawdown = peak_pnl - cumulative_pnl
  if drawdown > max_drawdown
    max_drawdown = drawdown
    max_drawdown_time = tracker.updated_at
  end

  pnl_timeline << {
    time: tracker.updated_at,
    tracker_id: tracker.id,
    symbol: tracker.symbol,
    status: tracker.status,
    pnl: pnl,
    cumulative: cumulative_pnl,
    hwm: tracker.high_water_mark_pnl.to_f
  }
end

puts "Peak PnL: ₹#{peak_pnl.round(2)} at #{peak_time&.strftime('%Y-%m-%d %H:%M:%S')}"
puts "Current PnL: ₹#{cumulative_pnl.round(2)}"
puts "Maximum Drawdown: ₹#{max_drawdown.round(2)} (#{((max_drawdown / peak_pnl) * 100).round(2)}%) at #{max_drawdown_time&.strftime('%Y-%m-%d %H:%M:%S')}"
puts "Total Decline: ₹#{(peak_pnl - cumulative_pnl).round(2)}"
puts ''

# Analyze losing trades
puts '❌ LOSING TRADES ANALYSIS'
puts '-' * 80
losing_trades = exited_trackers.select { |t| (t.last_pnl_rupees || 0).negative? }
total_loss = losing_trades.sum { |t| t.last_pnl_rupees.to_f }

puts "Total Losing Trades: #{losing_trades.count}"
puts "Total Loss: ₹#{total_loss.round(2)}"
puts "Average Loss per Trade: ₹#{(total_loss / losing_trades.count).round(2)}" if losing_trades.any?
puts ''

if losing_trades.any?
  puts 'Top 10 Worst Trades:'
  losing_trades.sort_by { |t| t.last_pnl_rupees.to_f }.first(10).each_with_index do |tracker, idx|
    puts "  #{idx + 1}. #{tracker.symbol} | Loss: ₹#{tracker.last_pnl_rupees.to_f.round(2)} (#{tracker.last_pnl_pct.to_f.round(2)}%) | " \
         "Entry: ₹#{tracker.entry_price.to_f.round(2)} | Exit: ₹#{begin
           tracker.exit_price.to_f.round(2)
         rescue StandardError
           'N/A'
         end} | " \
         "HWM: ₹#{tracker.high_water_mark_pnl.to_f.round(2)} | " \
         "Exit Reason: #{(tracker.meta.is_a?(Hash) ? tracker.meta['exit_reason'] : nil) || 'N/A'}"
  end
  puts ''
end

# Analyze winning trades
puts '✅ WINNING TRADES ANALYSIS'
puts '-' * 80
winning_trades = exited_trackers.select { |t| (t.last_pnl_rupees || 0).positive? }
total_profit = winning_trades.sum { |t| t.last_pnl_rupees.to_f }

puts "Total Winning Trades: #{winning_trades.count}"
puts "Total Profit: ₹#{total_profit.round(2)}"
puts "Average Profit per Trade: ₹#{(total_profit / winning_trades.count).round(2)}" if winning_trades.any?
puts ''

# Analyze by symbol/index
puts '📊 ANALYSIS BY SYMBOL/INDEX'
puts '-' * 80
by_symbol = all_trackers.group_by { |t| t.symbol || 'UNKNOWN' }
by_symbol.each do |symbol, trackers|
  total_pnl = trackers.sum { |t| t.last_pnl_rupees.to_f }
  exited_pnl = trackers.select(&:exited?).sum { |t| t.last_pnl_rupees.to_f }
  active_pnl = trackers.select(&:active?).sum { |t| t.last_pnl_rupees.to_f }

  next if total_pnl.zero? && trackers.none?(&:exited?)

  puts "#{symbol}:"
  puts "  Total Trades: #{trackers.count} (Exited: #{trackers.count(&:exited?)}, Active: #{trackers.count(&:active?)})"
  puts "  Total PnL: ₹#{total_pnl.round(2)} (Realized: ₹#{exited_pnl.round(2)}, Unrealized: ₹#{active_pnl.round(2)})"
  puts ''
end

# Analyze by index_key
puts '📊 ANALYSIS BY INDEX'
puts '-' * 80
by_index = {}
all_trackers.each do |tracker|
  meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
  index_key = meta['index_key'] || meta[:index_key] || tracker.symbol || 'UNKNOWN'
  by_index[index_key] ||= []
  by_index[index_key] << tracker
end

by_index.each do |index_key, trackers|
  total_pnl = trackers.sum { |t| t.last_pnl_rupees.to_f }
  exited_pnl = trackers.select(&:exited?).sum { |t| t.last_pnl_rupees.to_f }
  active_pnl = trackers.select(&:active?).sum { |t| t.last_pnl_rupees.to_f }

  next if total_pnl.zero? && trackers.none?(&:exited?)

  puts "#{index_key}:"
  puts "  Total Trades: #{trackers.count} (Exited: #{trackers.count(&:exited?)}, Active: #{trackers.count(&:active?)})"
  puts "  Total PnL: ₹#{total_pnl.round(2)} (Realized: ₹#{exited_pnl.round(2)}, Unrealized: ₹#{active_pnl.round(2)})"
  puts "  Winners: #{trackers.count { |t| t.exited? && (t.last_pnl_rupees || 0).positive? }}"
  puts "  Losers: #{trackers.count { |t| t.exited? && (t.last_pnl_rupees || 0).negative? }}"
  puts ''
end

# Analyze drawdowns from HWM
puts '📉 DRAWDOWN ANALYSIS'
puts '-' * 80
positions_with_drawdown = all_trackers.select do |t|
  t.high_water_mark_pnl.present? && t.high_water_mark_pnl.to_f.positive? &&
    t.last_pnl_rupees.present? && t.last_pnl_rupees.to_f < t.high_water_mark_pnl.to_f
end

if positions_with_drawdown.any?
  puts "Positions that dropped from HWM: #{positions_with_drawdown.count}"
  positions_with_drawdown.sort_by do |t|
    (t.high_water_mark_pnl.to_f - t.last_pnl_rupees.to_f)
  end.last(10).reverse_each do |tracker|
    drawdown = tracker.high_water_mark_pnl.to_f - tracker.last_pnl_rupees.to_f
    drawdown_pct = tracker.high_water_mark_pnl.to_f.positive? ? (drawdown / tracker.high_water_mark_pnl.to_f * 100) : 0
    puts "  #{tracker.symbol} | HWM: ₹#{tracker.high_water_mark_pnl.to_f.round(2)} | Current: ₹#{tracker.last_pnl_rupees.to_f.round(2)} | " \
         "Drawdown: ₹#{drawdown.round(2)} (#{drawdown_pct.round(2)}%) | Status: #{tracker.status}"
  end
  puts ''
end

# Analyze exit reasons
puts '🚪 EXIT REASONS ANALYSIS'
puts '-' * 80
exit_reasons = {}
exited_trackers.each do |tracker|
  meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
  reason = meta['exit_reason'] || meta[:exit_reason] || 'UNKNOWN'
  exit_reasons[reason] ||= { count: 0, total_pnl: 0.0 }
  exit_reasons[reason][:count] += 1
  exit_reasons[reason][:total_pnl] += tracker.last_pnl_rupees.to_f
end

exit_reasons.sort_by { |_k, v| v[:total_pnl] }.each do |reason, data|
  avg_pnl = data[:total_pnl] / data[:count]
  puts "#{reason}:"
  puts "  Count: #{data[:count]}"
  puts "  Total PnL: ₹#{data[:total_pnl].round(2)}"
  puts "  Avg PnL: ₹#{avg_pnl.round(2)}"
  puts ''
end

# Timeline of major events
puts '⏰ TIMELINE OF MAJOR EVENTS'
puts '-' * 80
significant_events = pnl_timeline.select do |event|
  event[:pnl].abs > 1000 || # Large individual PnL
    (event[:cumulative] - peak_pnl).abs > 5000 # Significant cumulative change
end

significant_events.sort_by { |e| e[:time] }.each do |event|
  puts "#{event[:time].strftime('%Y-%m-%d %H:%M:%S')} | " \
       "Tracker #{event[:tracker_id]} | #{event[:symbol]} | " \
       "PnL: ₹#{event[:pnl].round(2)} | Cumulative: ₹#{event[:cumulative].round(2)} | " \
       "Status: #{event[:status]}"
end

puts "\n#{'=' * 80}"
puts 'ANALYSIS COMPLETE'
puts "#{'=' * 80}\n"
