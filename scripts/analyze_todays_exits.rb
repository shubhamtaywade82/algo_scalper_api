# frozen_string_literal: true

# Analyze today's exited position trackers: metadata, exit reasons, PnL, and potential bugs.
# Usage: rails runner scripts/analyze_todays_exits.rb [DATE]
# Date format: YYYY-MM-DD (default: today in app timezone)

date_arg = ARGV[0]
date = date_arg ? Date.parse(date_arg) : Time.zone.today
range = date.beginning_of_day..date.end_of_day

exited = PositionTracker.paper.exited.where(exited_at: range).order(exited_at: :asc)

puts "\n#{'=' * 100}"
puts "EXITED POSITIONS ANALYSIS — #{date} (IST)"
puts "#{'=' * 100}"
puts "Total exited (paper): #{exited.count}"
puts ""

# last_pnl_pct is stored as DECIMAL (0.05 = 5%); display as percentage
def pct_display(val)
  return "—" if val.nil?
  "#{(val.to_f * 100.0).round(2)}%"
end

exited.each_with_index do |t, i|
  entry = t.created_at
  exit_time = t.exited_at
  duration_min = entry && exit_time ? ((exit_time - entry) / 60.0).round(1) : nil

  meta = t.meta || {}
  exit_path = meta["exit_path"] || t.exit_reason || "—"
  entry_path = meta["entry_path"] || meta.dig("entry_metadata", "entry_path") || "—"
  index_key = meta["index_key"] || "—"
  initial_sl_pct = meta["initial_sl_pct"]
  profit_floor_rupees = meta["profit_floor_rupees"]

  puts "--- Position #{i + 1} | #{t.order_no} | #{t.symbol} ---"
  puts "  Entry:     #{entry&.strftime('%H:%M')}  Exit: #{exit_time&.strftime('%H:%M')}  Duration: #{duration_min} min"
  puts "  PnL:       ₹#{t.last_pnl_rupees&.round(2)}  |  PnL %: #{pct_display(t.last_pnl_pct)} (stored decimal: #{t.last_pnl_pct})"
  puts "  Exit path: #{exit_path}"
  puts "  Entry path: #{entry_path}  |  Index: #{index_key}"
  puts "  initial_sl_pct: #{initial_sl_pct}  |  profit_floor_rupees: #{profit_floor_rupees}" if initial_sl_pct || profit_floor_rupees
  puts ""
end

puts "#{'=' * 100}"
puts "EXIT PATH SUMMARY"
puts "#{'=' * 100}"
by_path = exited.group_by { |t| (t.meta || {})["exit_path"] || t.exit_reason || "unknown" }
by_path.each { |path, list| puts "  #{path}: #{list.size}" }
puts ""
