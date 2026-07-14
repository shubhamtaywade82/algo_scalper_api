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
#
# `run_board_lifecycle` instead studies the full premium lifecycle (entry ->
# peak -> decay) for every strike from ATM-N to ATM+N, both CE and PE,
# anchored at a single timestamp (defaults to session open, 09:15 IST).
#
#   bundle exec rake 'research:run_board_lifecycle[NIFTY,2026-07-10,24982,WEEK]'
#   bundle exec rake 'research:run_board_lifecycle[NIFTY,2026-07-10,24982,WEEK,10,09:15]'

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

  desc "Study the full premium lifecycle (entry -> peak -> decay) across ATM+/-N strikes for a session"
  task :run_board_lifecycle, %i[symbol date spot expiry_flag max_distance entry_time] => :environment do |_t, args|
    symbol = args[:symbol].presence || raise(ArgumentError, "symbol is required")
    date = Date.parse(args[:date].to_s)
    spot = args[:spot].to_f
    expiry_flag = args[:expiry_flag].presence || "WEEK"
    max_distance = (args[:max_distance] || 10).to_i
    entry_time = args[:entry_time].presence || "09:15"
    entry_ts = Time.zone.parse("#{date} #{entry_time}")

    puts "\n#{'=' * 100}"
    puts "Premium lifecycle board — #{symbol} #{expiry_flag} #{date} entry=#{entry_ts} ATM+/-#{max_distance}"
    puts '=' * 100

    ranked = Research::LifecycleRunner.run(
      symbol: symbol, spot: spot, expiry_flag: expiry_flag, entry_ts: entry_ts,
      from_date: date.strftime("%Y-%m-%d"), to_date: (date + 1).strftime("%Y-%m-%d"), max_distance: max_distance
    )

    if ranked.empty?
      puts "No lifecycles produced (check symbol/date/expiry_flag)."
      next
    end

    printf("%-8s %-6s %-10s %10s %10s %10s %12s %10s\n",
           "Strike", "Type", "Status", "PeakRet%", "MinToPeak", "MaxDD%", "DecayStart", "EndRet%")
    ranked.each do |lifecycle|
      printf("%-8s %-6s %-10s %10s %10s %10s %12s %10s\n",
             lifecycle.strike_label, lifecycle.option_type, lifecycle.status,
             lifecycle.peak_return_pct || "-", lifecycle.minutes_to_peak || "-",
             lifecycle.max_drawdown_after_peak_pct || "-",
             lifecycle.decay_start_ts&.strftime("%H:%M") || "-", lifecycle.end_return_pct || "-")
    end
  end
end
