# frozen_string_literal: true

namespace :trading do
  desc <<~DESC.squish
    Signal feedback analysis: correlates trading signal conditions with trade PnL outcomes.
    Shows win rate, avg PnL, and best/worst conditions.
    DAYS=7 (default), INDEX=nifty|banknifty|sensex, MIN_TRADES=10, JSON=1
  DESC
  task signal_feedback: :environment do
    days = ENV.fetch('DAYS', '7').to_i
    index_filter = ENV['INDEX']&.upcase
    min_trades = ENV.fetch('MIN_TRADES', '10').to_i
    since = days.days.ago.beginning_of_day

    # Step 1: Get all entered signals with their conditions
    entered_signals = TradingSignal
      .where(created_at: since..)
      .where("metadata->>'entry_outcome' = 'entered'")
      .order(:created_at)

    if index_filter
      entered_signals = entered_signals.where(index_key: index_filter)
    end

    signals = entered_signals.to_a
    if signals.empty?
      puts "No entered signals found in the last #{days} days."
      next
    end

    # Step 2: For each signal, find the matching position tracker and trade analytics
    results = signals.map do |signal|
      # Find position tracker by index_key + signal_timestamp proximity
      tracker = PositionTracker
        .where(index_key: signal.index_key)
        .where(signal_timestamp: (signal.signal_timestamp - 5.minutes)..(signal.signal_timestamp + 2.minutes))
        .order(:created_at)
        .first

      analytics = tracker&.trade_analytics
      telemetry = tracker&.trade_telemetry

      {
        signal: signal,
        tracker: tracker,
        analytics: analytics,
        telemetry: telemetry,
        pnl: telemetry&.pnl_rupees&.to_f || 0.0,
        exit_reason: tracker&.exit_reason || 'open',
        duration_seconds: analytics&.duration_seconds,
        meta: signal.metadata || {}
      }
    end

    # Step 3: Filter to completed trades only
    completed = results.reject { |r| r[:tracker]&.status == 'active' || r[:tracker].nil? }
    all_trades = completed.size

    if all_trades < min_trades
      puts "Only #{all_trades} completed trades (min #{min_trades}). Showing available data anyway."
    end

    # Step 4: Aggregate by conditions
    puts "=" * 80
    puts "SIGNAL FEEDBACK ANALYSIS (#{since.strftime('%d %b %Y')} — #{Time.current.strftime('%d %b %Y')})"
    puts "=" * 80
    puts ""

    # Overall stats
    wins = completed.count { |r| r[:pnl] > 0 }
    losses = completed.count { |r| r[:pnl] < 0 }
    flat = completed.count { |r| r[:pnl] == 0 }
    total_pnl = completed.sum { |r| r[:pnl] }
    avg_pnl = all_trades > 0 ? total_pnl / all_trades : 0
    win_rate = all_trades > 0 ? (wins.to_f / all_trades * 100).round(1) : 0

    puts "OVERALL: #{all_trades} trades | #{wins}W #{losses}L #{flat}F | Win: #{win_rate}% | PnL: ₹#{total_pnl.round(2)} | Avg: ₹#{avg_pnl.round(2)}"
    puts ""

    # By index
    puts "--- BY INDEX ---"
    by_index = completed.group_by { |r| r[:signal].index_key }
    by_index.sort_by { |k, _| k }.each do |idx, trades|
      w = trades.count { |r| r[:pnl] > 0 }
      l = trades.count { |r| r[:pnl] < 0 }
      pnl = trades.sum { |r| r[:pnl] }
      wr = trades.size > 0 ? (w.to_f / trades.size * 100).round(1) : 0
      avg = trades.size > 0 ? pnl / trades.size : 0
      puts "  #{idx}: #{trades.size} trades | #{w}W #{l}L | Win: #{wr}% | PnL: ₹#{pnl.round(2)} | Avg: ₹#{avg.round(2)}"
    end
    puts ""

    # By direction
    puts "--- BY DIRECTION ---"
    by_dir = completed.group_by { |r| r[:signal].direction }
    by_dir.sort_by { |k, _| k }.each do |dir, trades|
      w = trades.count { |r| r[:pnl] > 0 }
      l = trades.count { |r| r[:pnl] < 0 }
      pnl = trades.sum { |r| r[:pnl] }
      wr = trades.size > 0 ? (w.to_f / trades.size * 100).round(1) : 0
      avg = trades.size > 0 ? pnl / trades.size : 0
      puts "  #{dir}: #{trades.size} trades | #{w}W #{l}L | Win: #{wr}% | PnL: ₹#{pnl.round(2)} | Avg: ₹#{avg.round(2)}"
    end
    puts ""

    # By regime
    puts "--- BY REGIME ---"
    by_regime = completed.group_by { |r| r[:meta]['regime'] || 'unknown' }
    by_regime.sort_by { |_, v| -v.size }.each do |regime, trades|
      w = trades.count { |r| r[:pnl] > 0 }
      l = trades.count { |r| r[:pnl] < 0 }
      pnl = trades.sum { |r| r[:pnl] }
      wr = trades.size > 0 ? (w.to_f / trades.size * 100).round(1) : 0
      avg = trades.size > 0 ? pnl / trades.size : 0
      puts "  #{regime}: #{trades.size} trades | #{w}W #{l}L | Win: #{wr}% | PnL: ₹#{pnl.round(2)} | Avg: ₹#{avg.round(2)}"
    end
    puts ""

    # By SMC decision
    puts "--- BY SMC DECISION ---"
    by_smc = completed.group_by { |r| r[:meta]['smc_decision'] || 'none' }
    by_smc.sort_by { |_, v| -v.size }.each do |dec, trades|
      w = trades.count { |r| r[:pnl] > 0 }
      l = trades.count { |r| r[:pnl] < 0 }
      pnl = trades.sum { |r| r[:pnl] }
      wr = trades.size > 0 ? (w.to_f / trades.size * 100).round(1) : 0
      avg = trades.size > 0 ? pnl / trades.size : 0
      puts "  #{dec}: #{trades.size} trades | #{w}W #{l}L | Win: #{wr}% | PnL: ₹#{pnl.round(2)} | Avg: ₹#{avg.round(2)}"
    end
    puts ""

    # By exit reason
    puts "--- BY EXIT REASON ---"
    by_exit = completed.group_by { |r| r[:exit_reason] }
    by_exit.sort_by { |_, v| -v.size }.each do |reason, trades|
      w = trades.count { |r| r[:pnl] > 0 }
      l = trades.count { |r| r[:pnl] < 0 }
      pnl = trades.sum { |r| r[:pnl] }
      avg = trades.size > 0 ? pnl / trades.size : 0
      puts "  #{reason}: #{trades.size} trades | #{w}W #{l}L | PnL: ₹#{pnl.round(2)} | Avg: ₹#{avg.round(2)}"
    end
    puts ""

    # ADX analysis (if we have data)
    adx_trades = completed.select { |r| r[:meta]['adx_value'].to_f > 0 }
    if adx_trades.any?
      puts "--- BY ADX RANGE ---"
      adx_bins = {
        '20-25 (weak)' => adx_trades.select { |r| r[:meta]['adx_value'].to_f.between?(20, 25) },
        '25-30 (moderate)' => adx_trades.select { |r| r[:meta]['adx_value'].to_f.between?(25, 30) },
        '30-40 (strong)' => adx_trades.select { |r| r[:meta]['adx_value'].to_f.between?(30, 40) },
        '40+ (very strong)' => adx_trades.select { |r| r[:meta]['adx_value'].to_f > 40 }
      }
      adx_bins.each do |label, trades|
        next if trades.empty?
        w = trades.count { |r| r[:pnl] > 0 }
        pnl = trades.sum { |r| r[:pnl] }
        wr = trades.size > 0 ? (w.to_f / trades.size * 100).round(1) : 0
        avg = trades.size > 0 ? pnl / trades.size : 0
        puts "  ADX #{label}: #{trades.size} trades | Win: #{wr}% | PnL: ₹#{pnl.round(2)} | Avg: ₹#{avg.round(2)}"
      end
      puts ""
    end

    # Confidence score analysis (if we have data)
    conf_trades = completed.select { |r| r[:signal].confidence_score.to_f > 0 }
    if conf_trades.any?
      puts "--- BY CONFIDENCE SCORE ---"
      conf_bins = {
        '0.8-1.0 (very high)' => conf_trades.select { |r| r[:signal].confidence_score.to_f.between?(0.8, 1.0) },
        '0.6-0.8 (high)' => conf_trades.select { |r| r[:signal].confidence_score.to_f.between?(0.6, 0.8) },
        '0.4-0.6 (medium)' => conf_trades.select { |r| r[:signal].confidence_score.to_f.between?(0.4, 0.6) },
        '<0.4 (low)' => conf_trades.select { |r| r[:signal].confidence_score.to_f < 0.4 }
      }
      conf_bins.each do |label, trades|
        next if trades.empty?
        w = trades.count { |r| r[:pnl] > 0 }
        pnl = trades.sum { |r| r[:pnl] }
        wr = trades.size > 0 ? (w.to_f / trades.size * 100).round(1) : 0
        avg = trades.size > 0 ? pnl / trades.size : 0
        puts "  Conf #{label}: #{trades.size} trades | Win: #{wr}% | PnL: ₹#{pnl.round(2)} | Avg: ₹#{avg.round(2)}"
      end
      puts ""
    end

    # Best and worst trades
    if completed.any?
      sorted = completed.sort_by { |r| -r[:pnl] }
      best = sorted.first
      worst = sorted.last

      puts "--- BEST TRADE ---"
      puts "  #{best[:signal].index_key} #{best[:signal].direction} @ #{best[:signal].created_at.strftime('%H:%M')}"
      puts "  PnL: ₹#{best[:pnl].round(2)} | Exit: #{best[:exit_reason]}"
      puts "  Conditions: regime=#{best[:meta]['regime']}, smc=#{best[:meta]['smc_decision']}, adx=#{best[:meta]['adx_value']}"
      puts ""

      puts "--- WORST TRADE ---"
      puts "  #{worst[:signal].index_key} #{worst[:signal].direction} @ #{worst[:signal].created_at.strftime('%H:%M')}"
      puts "  PnL: ₹#{worst[:pnl].round(2)} | Exit: #{worst[:exit_reason]}"
      puts "  Conditions: regime=#{worst[:meta]['regime']}, smc=#{worst[:meta]['smc_decision']}, adx=#{worst[:meta]['adx_value']}"
      puts ""
    end

    # Recommendations
    puts "--- RECOMMENDATIONS ---"
    if by_regime.any?
      best_regime = by_regime.max_by { |_, trades| trades.sum { |r| r[:pnl] } }
      worst_regime = by_regime.min_by { |_, trades| trades.sum { |r| r[:pnl] } }
      puts "  Best regime: #{best_regime[0]} (₹#{best_regime[1].sum { |r| r[:pnl] }.round(2)} total)"
      puts "  Worst regime: #{worst_regime[0]} (₹#{worst_regime[1].sum { |r| r[:pnl] }.round(2)} total)"
    end

    if adx_trades.any?
      good_adx = adx_bins.select { |_, trades| trades.any? && trades.sum { |r| r[:pnl] } > 0 }
      bad_adx = adx_bins.select { |_, trades| trades.any? && trades.sum { |r| r[:pnl] } < 0 }
      puts "  Profitable ADX ranges: #{good_adx.keys.join(', ')}" if good_adx.any?
      puts "  Unprofitable ADX ranges: #{bad_adx.keys.join(', ')}" if bad_adx.any?
    end

    if ENV['JSON'].to_s == '1'
      json_output = {
        period: { from: since, to: Time.current },
        overall: { trades: all_trades, wins: wins, losses: losses, win_rate: win_rate, total_pnl: total_pnl.round(2), avg_pnl: avg_pnl.round(2) },
        by_index: by_index.transform_values { |trades| { count: trades.size, pnl: trades.sum { |r| r[:pnl] }.round(2) } },
        by_direction: by_dir.transform_values { |trades| { count: trades.size, pnl: trades.sum { |r| r[:pnl] }.round(2) } },
        by_regime: by_regime.transform_values { |trades| { count: trades.size, pnl: trades.sum { |r| r[:pnl] }.round(2) } },
        by_exit_reason: by_exit.transform_values { |trades| { count: trades.size, pnl: trades.sum { |r| r[:pnl] }.round(2) } }
      }
      puts JSON.pretty_generate(json_output)
    end
  end
end
