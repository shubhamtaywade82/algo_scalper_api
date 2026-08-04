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

  desc "Generate regime-driven signals over a date range and rank exit strategies per regime bucket"
  task :run_regime_scan, %i[symbol from_date to_date expiry_flag] => :environment do |_t, args|
    symbol = args[:symbol].presence || raise(ArgumentError, "symbol is required")
    from_date = args[:from_date].presence || raise(ArgumentError, "from_date is required")
    to_date = args[:to_date].presence || raise(ArgumentError, "to_date is required")
    expiry_flag = args[:expiry_flag].presence || "WEEK"

    puts "\n#{'=' * 100}"
    puts "Regime scan — #{symbol} #{from_date} to #{to_date}"
    puts '=' * 100

    signals = Research::RegimeSignalGenerator.run(symbol: symbol, from_date: from_date, to_date: to_date)
    puts "#{signals.size} regime-driven signals generated."

    signals.each do |signal|
      Research::Pipeline.run(signal: signal, expiry_flags: [expiry_flag], max_distance: 0)
    end

    buckets = Research::RegimeExitReport.call(scope: Research::OptionCandidate.where(status: "scored"))

    if buckets.empty?
      puts "No scored candidates produced (check symbol/date range/candle data availability)."
      next
    end

    buckets.each do |bucket|
      puts "\n#{'-' * 100}"
      puts "Regime: #{bucket[:context].map { |k, v| "#{k}=#{v}" }.join(', ')} (n=#{bucket[:sample_size]})"
      puts '-' * 100
      printf("%-20s %10s %8s %8s %10s\n", "Strategy", "AvgRet%", "Win%", "PF", "Sharpe")
      bucket[:strategies].each do |name, stats|
        printf("%-20s %10s %8s %8s %10s\n",
               name, stats[:avg_return_pct], stats[:win_rate_pct], stats[:profit_factor], stats[:sharpe_ratio])
      end
    end
  end
  desc "Grid-search dynamic hold/exit thresholds (theta barrier, hard SL, IV crush) over scored candidates"
  task :sweep_hold_exit, %i[status] => :environment do |_t, args|
    status = args[:status].presence || "scored"

    puts "\n#{'=' * 100}"
    puts "Dynamic hold/exit sweep — Research::OptionCandidate.where(status: #{status.inspect})"
    puts '=' * 100

    rows = Research::HoldExitSweep.run(scope: Research::OptionCandidate.where(status: status))

    if rows.all? { |r| r[:sample_size].zero? }
      puts "No candidates with usable bars/entry data (run research:run_signal or research:run_regime_scan first)."
      next
    end

    printf("%-8s %-8s %-8s %10s %8s %10s\n", "Theta", "SL%", "IVCrush%", "AvgRet%", "Win%", "AvgHoldMin")
    rows.each do |r|
      printf("%-8s %-8s %-8s %10s %8s %10s\n",
             r[:theta_minutes], (r[:hard_sl_pct] * 100).round, (r[:iv_crush_pct] * 100).round,
             r[:avg_return_pct], r[:win_rate_pct], r[:avg_holding_minutes])
    end
  end

  desc "Forensic-scan research_option_bars for explosive premium moves (open->peak) and their spot/IV context"
  task :scan_explosive_moves, %i[symbol from_date to_date expiry_flag min_gain_pct min_premium] => :environment do |_t, args|
    symbol = args[:symbol].presence || raise(ArgumentError, "symbol is required")
    from_date = args[:from_date].presence || raise(ArgumentError, "from_date is required")
    to_date = args[:to_date].presence || raise(ArgumentError, "to_date is required")
    expiry_flag = args[:expiry_flag].presence
    min_gain_pct = (args[:min_gain_pct] || 0.5).to_f
    min_premium = (args[:min_premium] || 10.0).to_f

    puts "\n#{'=' * 100}"
    puts "Explosive move scan — #{symbol} #{from_date} to #{to_date} (>= #{(min_gain_pct * 100).round}% gain, min premium #{min_premium})"
    puts '=' * 100

    moves = Research::ExplosiveMoveScanner.scan(
      symbol: symbol, from_date: from_date, to_date: to_date, expiry_flag: expiry_flag,
      min_gain_pct: min_gain_pct, min_premium: min_premium
    )

    if moves.empty?
      puts "No moves found (check date range / research_option_bars coverage / lower min_gain_pct)."
      next
    end

    puts "#{moves.size} explosive moves found. Top 50 by gain%:\n\n"
    printf("%-12s %-4s %8s %8s %8s %6s %6s %10s %10s %10s %8s %8s\n",
           "Date", "Type", "Strike", "Open", "Peak", "Gain%", "Time", "SpotStart", "SpotEnd", "SpotMv%", "IVStart", "IVPeak")
    moves.first(50).each do |r|
      printf("%-12s %-4s %8s %8s %8s %6s %6s %10s %10s %10s %8s %8s\n",
             r[:date], r[:option_type], r[:strike], r[:open_price], r[:peak_price], r[:gain_pct],
             r[:time_of_peak].strftime("%H:%M"), r[:spot_start], r[:spot_end], r[:spot_move_pct] || "-",
             r[:iv_start] || "-", r[:iv_peak] || "-")
    end

    puts "\n#{'-' * 100}"
    puts "By hour of peak:"
    moves.group_by { |r| r[:time_of_peak].hour }.sort.each do |hour, group|
      puts "  #{hour}:00-#{hour}:59  n=#{group.size}  avg_gain=#{(group.sum { |r| r[:gain_pct] } / group.size.to_f).round(1)}%"
    end

    puts "\nBy weekday:"
    moves.group_by { |r| r[:date].strftime("%A") }.each do |wday, group|
      puts "  #{wday.ljust(10)} n=#{group.size}  avg_gain=#{(group.sum { |r| r[:gain_pct] } / group.size.to_f).round(1)}%"
    end

    with_iv = moves.select { |r| r[:iv_start] }
    if with_iv.any?
      low_iv, high_iv = with_iv.partition { |r| r[:iv_start] < 12.0 }
      puts "\nBy starting IV:"
      puts "  IV < 12   n=#{low_iv.size}  avg_gain=#{low_iv.any? ? (low_iv.sum { |r| r[:gain_pct] } / low_iv.size.to_f).round(1) : '-'}%"
      puts "  IV >= 12  n=#{high_iv.size}  avg_gain=#{high_iv.any? ? (high_iv.sum { |r| r[:gain_pct] } / high_iv.size.to_f).round(1) : '-'}%"
    end
  end
end
