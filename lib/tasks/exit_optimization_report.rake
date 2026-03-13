# frozen_string_literal: true

namespace :trading do
  desc 'Exit optimization report using PositionTracker, TradeAnalytic, and DrawdownSchedule'
  task exit_optimization_report: :environment do
    require 'bigdecimal'

    days = (ENV['DAYS'] || '5').to_i
    since = days.positive? ? days.days.ago.beginning_of_day : nil

    scope = PositionTracker.exited_paper
    scope = scope.where(exited_at: since..) if since
    exited = scope.includes(:trade_analytic).order(exited_at: :asc)

    if exited.empty?
      puts 'No exited paper positions found for report window.'
      next
    end

    puts '=' * 100
    puts 'EXIT OPTIMIZATION REPORT'
    puts '=' * 100
    puts "Window: last #{days.positive? ? days : 'ALL'} day(s)"
    puts "Total exited paper positions: #{exited.size}"
    puts

    # ----- Data audit: analytics / telemetry coverage -----
    trade_analytics_count = exited.count { |t| t.trade_analytic.present? }
    telemetry_count = TradeTelemetry.where(tracker_id: exited.map(&:id)).count

    puts 'DATA AUDIT'
    puts '-' * 100
    puts "TradeAnalytic coverage: #{trade_analytics_count} / #{exited.size} " \
         "(#{(trade_analytics_count.to_f / exited.size * 100).round(1)}%)"
    puts "TradeTelemetry coverage: #{telemetry_count} / #{exited.size} " \
         "(#{(telemetry_count.to_f / exited.size * 100).round(1)}%)"
    puts

    # ----- Basic PnL stats -----
    winners = exited.select { |t| (t.last_pnl_rupees || 0).to_f.positive? }
    losers  = exited.select { |t| (t.last_pnl_rupees || 0).to_f.negative? }
    breakeven = exited.size - winners.size - losers.size

    realized_pnl = exited.sum { |t| (t.last_pnl_rupees || 0).to_f }
    avg_pnl = realized_pnl / exited.size.to_f
    win_rate = winners.empty? ? 0.0 : (winners.size.to_f / exited.size * 100.0)

    puts 'PNL SUMMARY'
    puts '-' * 100
    puts "Winners:   #{winners.size}"
    puts "Losers:    #{losers.size}"
    puts "Breakeven: #{breakeven}"
    puts "Win rate:  #{win_rate.round(2)}%"
    puts "Total realized PnL: ₹#{realized_pnl.round(2)}"
    puts "Avg PnL per trade: ₹#{avg_pnl.round(2)}"
    puts

    # ----- High-water-mark vs final PnL -----
    with_hwm = exited.select { |t| (t.high_water_mark_pnl || 0).to_f.positive? }
    hwm_to_loss = with_hwm.select do |t|
      hwm = t.high_water_mark_pnl.to_f
      final = (t.last_pnl_rupees || 0).to_f
      hwm.positive? && final.negative?
    end

    puts 'HIGH WATER MARK VS FINAL PNL'
    puts '-' * 100
    if with_hwm.empty?
      puts 'No positions with recorded high_water_mark_pnl.'
    else
      share_hwm_loss = if hwm_to_loss.empty?
                         0.0
                       else
                         (hwm_to_loss.size.to_f / with_hwm.size * 100.0)
                       end
      puts "Positions with HWM: #{with_hwm.size}"
      puts "HWM > 0 but final PnL < 0: #{hwm_to_loss.size} " \
           "(#{share_hwm_loss.round(2)}% of positions-with-HWM)"
      drops = hwm_to_loss.map do |t|
        hwm = t.high_water_mark_pnl.to_f
        final = (t.last_pnl_rupees || 0).to_f
        ((hwm - final) / hwm * 100.0)
      end
      if drops.any?
        avg_drop = drops.sum / drops.size
        max_drop = drops.max
        puts "Average drop from peak (HWM→exit) for HWM→loss set: #{avg_drop.round(2)}%"
        puts "Max drop from peak in HWM→loss set: #{max_drop.round(2)}%"
      end
    end
    puts

    # ----- Exit reason breakdown -----
    puts 'EXIT REASON BREAKDOWN'
    puts '-' * 100
    grouped_by_reason = exited.group_by do |t|
      meta = t.meta.is_a?(Hash) ? t.meta : {}
      meta['exit_reason'] || t.exit_reason || 'UNKNOWN'
    end

    grouped_by_reason.each do |reason, trackers|
      wins = trackers.count { |t| (t.last_pnl_rupees || 0).to_f.positive? }
      pnl_sum = trackers.sum { |t| (t.last_pnl_rupees || 0).to_f }
      hwm_sum = trackers.sum { |t| (t.high_water_mark_pnl || 0).to_f }
      reason_win_rate = trackers.empty? ? 0.0 : (wins.to_f / trackers.size * 100.0)
      puts "#{reason}:"
      puts "  Trades: #{trackers.size}"
      puts "  Win rate: #{reason_win_rate.round(2)}%"
      puts "  Total PnL: ₹#{pnl_sum.round(2)}"
      puts "  Avg HWM: ₹#{(hwm_sum / [trackers.size, 1].max).round(2)}"
    end
    puts

    # ----- DrawdownSchedule comparison -----
    puts 'DRAWDOWN SCHEDULE VS ACTUAL DROPS'
    puts '-' * 100
    dd_samples = []

    with_hwm.each do |t|
      hwm = t.high_water_mark_pnl.to_f
      final = (t.last_pnl_rupees || 0).to_f
      next if hwm <= 0

      entry_price = t.entry_price.to_f
      qty = (t.quantity || 0).to_i
      entry_value = entry_price * qty
      next unless entry_value.positive?

      peak_profit_pct = hwm / entry_value
      actual_drop_pct = (hwm - final) / hwm

      index_key = if t.meta.is_a?(Hash)
                    t.meta['index_key']
                  elsif t.instrument
                    t.instrument.symbol_name
                  end

      allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(
        peak_profit_pct,
        index_key: index_key
      )
      next unless allowed_dd

      dd_samples << {
        tracker: t,
        peak_profit_pct: peak_profit_pct,
        actual_drop_pct: actual_drop_pct,
        allowed_dd: allowed_dd
      }
    end

    if dd_samples.empty?
      puts 'No suitable samples (with HWM, valid entry, and DrawdownSchedule config) to compare.'
    else
      late_exits = dd_samples.select { |s| s[:actual_drop_pct] > s[:allowed_dd] }
      early_exits = dd_samples.select { |s| s[:actual_drop_pct] < s[:allowed_dd] * 0.5 }

      share_late = (late_exits.size.to_f / dd_samples.size * 100.0).round(2)
      share_early = (early_exits.size.to_f / dd_samples.size * 100.0).round(2)

      puts "Samples compared: #{dd_samples.size}"
      puts "Actual drop > allowed drawdown: #{late_exits.size} (#{share_late}%)"
      puts "Actual drop < 0.5 × allowed drawdown: #{early_exits.size} (#{share_early}%)"
    end
    puts

    # ----- MFE/MAE summary from TradeAnalytic -----
    analytics = exited.filter_map(&:trade_analytic)

    puts 'MFE / MAE SUMMARY (TradeAnalytic)'
    puts '-' * 100
    if analytics.empty?
      puts 'No TradeAnalytic records for this window.'
    else
      mfe_pcts = analytics.map(&:mfe_pct)
      mae_pcts = analytics.map(&:mae_pct)
      avg_mfe = mfe_pcts.sum / mfe_pcts.size.to_f
      avg_mae = mae_pcts.sum / mae_pcts.size.to_f
      puts "Trades with analytics: #{analytics.size}"
      puts "Avg MFE: #{(avg_mfe * 100.0).round(2)}%"
      puts "Avg MAE: #{(avg_mae * 100.0).round(2)}%"
    end
    puts

    puts '=' * 100
    puts 'REPORT COMPLETE'
    puts '=' * 100
  end

  desc 'Optimize trailing parameters using TradeAnalytic (MFE/MAE simulation)'
  task optimize_trailing_exits: :environment do
    indices = %w[NIFTY BANKNIFTY SENSEX]

    puts '=' * 100
    puts 'TRAILING PARAMETER OPTIMIZATION (Optimization::TrailingOptimizer)'
    puts '=' * 100
    puts

    indices.each do |index_key|
      optimizer = Optimization::TrailingOptimizer.new(index_key: index_key)
      result = optimizer.optimize

      if result.nil?
        puts "Index #{index_key}: no analytics data available."
        next
      end

      params = result[:best_params] || {}
      score = result[:score]

      puts "Index: #{index_key}"
      puts "  Trades analyzed: #{result[:trade_count]}"
      puts "  Best parameters:"
      puts "    early_trigger:      #{params[:early_trigger]}"
      puts "    breakeven_trigger:  #{params[:breakeven_trigger]}"
      puts "    activation_trigger: #{params[:activation_trigger]}"
      puts "    trailing_distance:  #{params[:trailing_distance]}"
      puts "  Aggregate simulated profit score: #{score.round(4)}"
      puts
    end

    puts '=' * 100
    puts 'OPTIMIZATION COMPLETE'
    puts '=' * 100
  end
end

