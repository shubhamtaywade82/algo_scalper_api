# lib/tasks/research.rake
# frozen_string_literal: true
#
# DHAN API RESEARCH PIPELINE
# Anchors a manual signal snapshot (symbol/spot/timestamp/direction) and runs
# it through Research::Pipeline: candidate strikes -> rolling option candle
# fetch -> normalized storage -> MFE/MAE/return scoring across ATM and
# ATM+/-N strikes.
#
# Usage:
#   bundle exec rake 'research:run_signal[NIFTY,2026-07-10 10:14:00,24982,bullish]'
#   bundle exec rake 'research:run_signal[NIFTY,2026-07-10 10:14:00,24982,bullish,WEEK,2]'

namespace :research do
  desc "Run the option-candidate research pipeline for a manual signal snapshot"
  task :run_signal, %i[symbol timestamp spot direction expiry_flag max_distance] => :environment do |_t, args|
    symbol = args[:symbol].presence || raise(ArgumentError, "symbol is required")
    signal_timestamp = Time.zone.parse(args[:timestamp].to_s) ||
                        raise(ArgumentError, "invalid timestamp: #{args[:timestamp]}")
    spot = args[:spot].to_f
    direction = args[:direction].presence || raise(ArgumentError, "direction is required (bullish|bearish)")
    expiry_flag = args[:expiry_flag].presence || "WEEK"
    max_distance = (args[:max_distance] || 2).to_i

    signal = Research::SignalSnapshotBuilder.build(
      underlying_symbol: symbol,
      signal_timestamp: signal_timestamp,
      direction: direction,
      spot_price: spot,
      strategy_name: "manual_rake_run"
    )

    puts "\n#{'=' * 100}"
    puts "Research::Signal##{signal.id} — #{signal.underlying_symbol} #{signal.direction} @ #{signal.spot_price} (#{signal.signal_timestamp})"
    puts '=' * 100

    ranked = Research::Pipeline.run(signal: signal, expiry_flags: [expiry_flag], max_distance: max_distance)

    if ranked.empty?
      puts "No candidates produced (direction may be no_trade, or symbol unsupported)."
      next
    end

    printf("%-10s %-6s %-10s %10s %10s %8s %8s %8s %10s\n",
           "Strike", "Type", "Status", "Entry", "Exit", "MFE%", "MAE%", "Ret%", "HoldMin")
    ranked.each do |candidate|
      printf("%-10s %-6s %-10s %10s %10s %8s %8s %8s %10s\n",
             candidate.strike_label, candidate.option_type, candidate.status,
             candidate.entry_price || "-", candidate.exit_price || "-",
             candidate.mfe_pct || "-", candidate.mae_pct || "-",
             candidate.return_pct || "-", candidate.holding_minutes || "-")
    end
  end
end
