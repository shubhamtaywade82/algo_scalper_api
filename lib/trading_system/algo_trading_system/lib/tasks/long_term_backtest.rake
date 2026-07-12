# lib/tasks/long_term_backtest.rake
# frozen_string_literal: true

namespace :backtest do
  desc "Run long-term backtest (5 years) in monthly batches for NIFTY/SENSEX"
  task :long_term, [:underlying, :strategy, :years] do |_t, args|
    require 'date'
    require 'json'
    require 'fileutils'
    require 'dotenv/load'
    require_relative '../../src/backtest/orchestrator'
    require_relative '../../src/strategies/trading_strategies'

    # 1. Configuration
    underlying = (args[:underlying] || 'nifty').downcase
    strategy   = (args[:strategy]   || 'bollinger_breakout').to_sym
    years      = (args[:years]      || 5).to_i

    token = ENV['DHAN_ACCESS_TOKEN']
    if token.nil? || token.empty?
      puts "❌ Error: DHAN_ACCESS_TOKEN not set in .env"
      next
    end

    initial_capital = 1_000_000.0
    current_capital = initial_capital

    end_date = Date.today - 1
    start_date = end_date - (365 * years)

    # Generate monthly chunks
    chunks = []
    curr = start_date
    while curr < end_date
      chunk_end = [curr.next_month - 1, end_date].min
      chunks << { from: curr.to_s, to: chunk_end.to_s }
      curr = curr.next_month
    end

    puts "🚀 Starting #{years}-Year Backtest for #{underlying.upcase}"
    puts "📈 Strategy: #{strategy.to_s.upcase}"
    puts "📅 Period:   #{start_date} to #{end_date} (#{chunks.size} monthly batches)"
    puts "💰 Capital:  ₹#{initial_capital}"
    puts "═" * 80

    all_trades = []
    results_dir = "./backtest_results/long_term_#{underlying}_#{strategy}_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    FileUtils.mkdir_p(results_dir)

    orchestrator = Backtest::Orchestrator.new(
      access_token: token,
      capital: initial_capital, # We will handle compounding manually or track total
      output_dir: results_dir
    )

    chunks.each_with_index do |chunk, index|
      puts "\n⏳ Batch #{index + 1}/#{chunks.size}: #{chunk[:from]} to #{chunk[:to]}"

      begin
        # Note: We keep capital constant for sizing or we could compound.
        # For simplicity and institutional benchmarking, we keep per-trade risk based on initial.
        config = {
          underlying: underlying,
          strategy: strategy,
          from_date: chunk[:from],
          to_date: chunk[:to],
          interval: 5,
          strikes: ['ATM', 'ATM+1', 'ATM-1'],
          option_type: 'CALL'
        }

        # Add a slight delay to respect rate limits between monthly batches
        sleep 1

        res = orchestrator.run_backtest(config: config)

        if res && res[:trades]
          month_trades = res[:trades]
          all_trades.concat(month_trades)

          month_pnl = month_trades.sum { |t| t[:pnl].to_f }
          puts "✅ Batch Complete. P&L: ₹#{month_pnl.round(2)} | Trades: #{month_trades.size}"
        else
          puts "⚠️ No data or trades for this period."
        end
      rescue => e
        puts "❌ Error in batch #{chunk[:from]}: #{e.message}"
        # Continue to next month instead of failing entirely
      end
    end

    # 2. Final Global Aggregation
    puts "\n" + "═" * 80
    puts "🏁 LONG-TERM BACKTEST COMPLETED"
    puts "═" * 80

    total_pnl = all_trades.sum { |t| t[:pnl].to_f }
    total_trades = all_trades.size
    wins = all_trades.count { |t| t[:status] == 'WIN' }
    win_rate = total_trades.positive? ? (wins.to_f / total_trades * 100).round(2) : 0

    # Calculate Max Drawdown on full history
    equity_curve = [initial_capital]
    all_trades.sort_by { |t| t[:exit_time] }.each do |t|
      equity_curve << equity_curve.last + t[:pnl].to_f
    end

    max_peak = equity_curve.first
    max_dd = 0.0
    equity_curve.each do |val|
      max_peak = [max_peak, val].max
      dd = (max_peak - val) / max_peak
      max_dd = [max_dd, dd].max
    end

    puts "📊 FINAL MULTI-YEAR STATS:"
    puts "  %-20s : %d" % ["Total Trades", total_trades]
    puts "  %-20s : %.2f%%" % ["Overall Win Rate", win_rate]
    puts "  %-20s : ₹%.2f" % ["Net P&L", total_pnl]
    puts "  %-20s : %.2f%%" % ["Max Drawdown", max_dd * 100]
    puts "  %-20s : ₹%.2f" % ["Final Equity", equity_curve.last]

    # Save master report
    master_report = {
      underlying: underlying,
      strategy: strategy,
      period: "#{start_date} to #{end_date}",
      summary: {
        total_trades: total_trades,
        win_rate: "#{win_rate}%",
        total_pnl: total_pnl.round(2),
        max_drawdown: "#{(max_dd * 100).round(2)}%",
        final_equity: equity_curve.last.round(2)
      },
      trades: all_trades
    }

    File.write("#{results_dir}/master_report.json", JSON.pretty_generate(master_report))
    puts "\n📂 Master report saved to #{results_dir}/master_report.json"
    puts "═" * 80 + "\n"
  end
end
