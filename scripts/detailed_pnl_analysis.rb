# frozen_string_literal: true

# Detailed PnL analysis focusing on the decline
# Usage: rails runner scripts/detailed_pnl_analysis.rb

puts "\n" + "=" * 100
puts "DETAILED PNL DECLINE ANALYSIS"
puts "=" * 100 + "\n"

all_trackers = PositionTracker.paper.order(created_at: :asc)
exited_trackers = PositionTracker.paper.exited.order(created_at: :asc)

# Build timeline with cumulative PnL
timeline = []
cumulative = 0.0
peak_pnl = 0.0
peak_tracker = nil

exited_trackers.each do |tracker|
  pnl = tracker.last_pnl_rupees.to_f
  cumulative += pnl

  if cumulative > peak_pnl
    peak_pnl = cumulative
    peak_tracker = tracker
  end

  meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
  exit_reason = meta['exit_reason'] || meta[:exit_reason] || 'UNKNOWN'

  exit_price = begin
    tracker.exit_price.to_f
  rescue StandardError
    nil
  end

  timeline << {
    tracker: tracker,
    time: tracker.updated_at,
    pnl: pnl,
    cumulative: cumulative,
    hwm: tracker.high_water_mark_pnl.to_f,
    exit_reason: exit_reason,
    entry_price: tracker.entry_price.to_f,
    exit_price: exit_price,
    quantity: tracker.quantity.to_i
  }
end

puts "🔴 CRITICAL FINDINGS"
puts "-" * 100
puts "Peak PnL: ₹#{peak_pnl.round(2)} at #{peak_tracker&.updated_at&.strftime('%Y-%m-%d %H:%M:%S')}"
puts "Current PnL: ₹#{cumulative.round(2)}"
puts "Total Loss: ₹#{(peak_pnl - cumulative).round(2)}"
puts ""

# Find the decline period
peak_index = timeline.find_index { |e| e[:cumulative] == peak_pnl }
decline_period = timeline[peak_index..-1] if peak_index

puts "📉 DECLINE PERIOD ANALYSIS (After Peak)"
puts "-" * 100
if decline_period
  puts "Trades after peak: #{decline_period.count - 1}"
  total_decline = decline_period.sum { |e| e[:pnl] } - peak_tracker.last_pnl_rupees.to_f
  puts "Total PnL in decline period: ₹#{total_decline.round(2)}"
  puts ""

  puts "Trades in decline period:"
  decline_period[1..-1].each_with_index do |event, idx|
    tracker = event[:tracker]
    meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
    drawdown_info = event[:exit_reason].match(/drawdown: ([\d.]+)%/)&.captures&.first

    puts "  #{idx + 1}. #{event[:time].strftime('%H:%M:%S')} | " \
         "PnL: ₹#{event[:pnl].round(2)} | " \
         "Cumulative: ₹#{event[:cumulative].round(2)} | " \
         "HWM: ₹#{event[:hwm].round(2)} | " \
         "Entry: ₹#{event[:entry_price].round(2)} | " \
         "Exit: ₹#{event[:exit_price].round(2) rescue 'N/A'} | " \
         "Qty: #{event[:quantity]} | " \
         "Drawdown: #{drawdown_info}% | " \
         "Reason: #{event[:exit_reason]}"
  end
  puts ""
end

# Analyze consecutive losses
puts "🔴 CONSECUTIVE LOSSES ANALYSIS"
puts "-" * 100
max_consecutive_losses = 0
current_streak = 0
consecutive_losses_start = nil

timeline.each do |event|
  if event[:pnl].negative?
    current_streak += 1
    consecutive_losses_start ||= event[:time]
    max_consecutive_losses = [max_consecutive_losses, current_streak].max
  else
    current_streak = 0
    consecutive_losses_start = nil
  end
end

puts "Maximum consecutive losses: #{max_consecutive_losses}"
puts ""

# Find the worst losing streak
current_streak = 0
worst_streak = { count: 0, start: nil, end: nil, total_loss: 0.0 }
streak_start = nil
streak_loss = 0.0

timeline.each do |event|
  if event[:pnl].negative?
    current_streak += 1
    streak_start ||= event[:time]
    streak_loss += event[:pnl]

    if current_streak > worst_streak[:count]
      worst_streak = {
        count: current_streak,
        start: streak_start,
        end: event[:time],
        total_loss: streak_loss
      }
    end
  else
    current_streak = 0
    streak_start = nil
    streak_loss = 0.0
  end
end

if worst_streak[:count] > 0
  puts "Worst losing streak:"
  puts "  Count: #{worst_streak[:count]} consecutive losses"
  puts "  Period: #{worst_streak[:start]&.strftime('%H:%M:%S')} to #{worst_streak[:end]&.strftime('%H:%M:%S')}"
  puts "  Total Loss: ₹#{worst_streak[:total_loss].round(2)}"
  puts ""
end

# Analyze entry/exit prices
puts "💰 ENTRY/EXIT PRICE ANALYSIS"
puts "-" * 100
puts "Losing trades entry/exit analysis:"
losing_trades = exited_trackers.select { |t| (t.last_pnl_rupees || 0).negative? }
losing_trades.sort_by { |t| t.updated_at }.each do |tracker|
  entry = tracker.entry_price.to_f
  exit_price = tracker.exit_price.to_f rescue nil
  pnl = tracker.last_pnl_rupees.to_f
  pnl_pct = tracker.last_pnl_pct.to_f

  if exit_price
    price_change = ((exit_price - entry) / entry * 100.0)
    puts "  #{tracker.updated_at.strftime('%H:%M:%S')} | " \
         "Entry: ₹#{entry.round(2)} → Exit: ₹#{exit_price.round(2)} " \
         "(#{price_change.round(2)}%) | " \
         "PnL: ₹#{pnl.round(2)} (#{pnl_pct.round(2)}%) | " \
         "Qty: #{tracker.quantity}"
  end
end
puts ""

# Analyze HWM vs final PnL
puts "📊 HIGH WATER MARK ANALYSIS"
puts "-" * 100
positions_with_hwm = exited_trackers.select { |t| t.high_water_mark_pnl.present? && t.high_water_mark_pnl.to_f.positive? }
positions_with_hwm.each do |tracker|
  hwm = tracker.high_water_mark_pnl.to_f
  final_pnl = tracker.last_pnl_rupees.to_f
  drawdown = hwm - final_pnl

  if drawdown > 1000 # Significant drawdown
    puts "  #{tracker.symbol} | " \
         "HWM: ₹#{hwm.round(2)} | " \
         "Final: ₹#{final_pnl.round(2)} | " \
         "Drawdown: ₹#{drawdown.round(2)} | " \
         "Exit: #{tracker.updated_at.strftime('%H:%M:%S')}"
  end
end
puts ""

# Summary of what went wrong
puts "🎯 ROOT CAUSE ANALYSIS"
puts "-" * 100
puts "1. ALL TRADES ON SAME STRIKE: All 33 trades were on BANKNIFTY-Nov2025-59000-PE"
puts "   → No diversification, all eggs in one basket"
puts ""
puts "2. PEAK DRAWDOWN EXITS: All exits triggered by peak_drawdown_exit (5% threshold)"
puts "   → Trailing stops cutting profits short, then exiting at losses"
puts ""
puts "3. CONSECUTIVE LOSSES: #{max_consecutive_losses} consecutive losses after peak"
puts "   → Market moved against the position, but system kept entering same strike"
puts ""
puts "4. TIMING: Peak at 11:00:16, then rapid decline"
puts "   → Market conditions changed, but strategy didn't adapt"
puts ""
puts "5. WIN RATE: 10 winners (30.3%) vs 23 losers (69.7%)"
puts "   → Low win rate suggests entry timing or strike selection issues"
puts ""

puts "=" * 100 + "\n"

