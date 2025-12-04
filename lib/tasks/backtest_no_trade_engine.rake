# frozen_string_literal: true

namespace :backtest do
  desc 'Backtest Supertrend + ADX strategy with No-Trade Engine on historical data'
  task :no_trade_engine, [:symbol, :days] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    days = (args[:days] || 90).to_i

    puts "\n" + '=' * 80
    puts "BACKTEST: #{symbol} with No-Trade Engine + Supertrend + ADX"
    puts "Period: Last #{days} days"
    puts '=' * 80

    begin
      service = BacktestServiceWithNoTradeEngine.run(
        symbol: symbol,
        interval_1m: '1',
        interval_5m: '5',
        days_back: days,
        supertrend_cfg: {
          period: 7,
          multiplier: 3.0
        },
        adx_min_strength: 0 # No ADX filter (let No-Trade Engine handle filtering)
      )

      service.print_summary

      # Save results to file
      results_file = Rails.root.join("tmp/backtest_no_trade_engine_#{symbol.downcase}_#{Date.today}.json")
      File.write(results_file, JSON.pretty_generate(service.summary))
      puts "\nResults saved to: #{results_file}"
    rescue StandardError => e
      puts "\n❌ Error: #{e.class} - #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc 'Compare backtest results: With vs Without No-Trade Engine'
  task :compare, [:symbol, :days] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    days = (args[:days] || 90).to_i

    puts "\n" + '=' * 80
    puts "COMPARISON BACKTEST: #{symbol}"
    puts "Period: Last #{days} days"
    puts '=' * 80

    # Backtest WITHOUT No-Trade Engine (using existing BacktestService)
    puts "\n[1/2] Running backtest WITHOUT No-Trade Engine..."
    begin
      strategy = SupertrendAdxStrategy.new(
        series: nil, # Will be set in BacktestService
        supertrend_cfg: { period: 7, multiplier: 3.0 },
        adx_min_strength: 0
      )

      service_without = BacktestService.run(
        symbol: symbol,
        interval: '5',
        days_back: days,
        strategy: strategy
      )

      summary_without = service_without.summary
      puts "\nWITHOUT No-Trade Engine:"
      puts "  Trades: #{summary_without[:total_trades]}"
      puts "  Win Rate: #{summary_without[:win_rate]}%"
      puts "  Expectancy: #{summary_without[:expectancy]}%"
      puts "  Total P&L: #{summary_without[:total_pnl_percent]}%"
    rescue StandardError => e
      puts "  ❌ Error: #{e.message}"
      summary_without = {}
    end

    # Backtest WITH No-Trade Engine
    puts "\n[2/2] Running backtest WITH No-Trade Engine..."
    begin
      service_with = BacktestServiceWithNoTradeEngine.run(
        symbol: symbol,
        interval_1m: '1',
        interval_5m: '5',
        days_back: days,
        supertrend_cfg: {
          period: 7,
          multiplier: 3.0
        },
        adx_min_strength: 0
      )

      summary_with = service_with.summary
      puts "\nWITH No-Trade Engine:"
      puts "  Trades: #{summary_with[:total_trades]}"
      puts "  Win Rate: #{summary_with[:win_rate]}%"
      puts "  Expectancy: #{summary_with[:expectancy]}%"
      puts "  Total P&L: #{summary_with[:total_pnl_percent]}%"
      puts "  Phase 1 Blocked: #{summary_with[:no_trade_stats][:phase1_blocked]}"
      puts "  Phase 2 Blocked: #{summary_with[:no_trade_stats][:phase2_blocked]}"
      puts "  Signals Generated: #{summary_with[:no_trade_stats][:signal_generated]}"
    rescue StandardError => e
      puts "  ❌ Error: #{e.message}"
      summary_with = {}
    end

    # Comparison
    if summary_without.any? && summary_with.any?
      puts "\n" + '=' * 80
      puts "COMPARISON SUMMARY"
      puts '=' * 80
      puts "Trades:        #{summary_without[:total_trades]} → #{summary_with[:total_trades]} (#{summary_with[:total_trades] - summary_without[:total_trades]})"
      puts "Win Rate:      #{summary_without[:win_rate]}% → #{summary_with[:win_rate]}% (#{summary_with[:win_rate] - summary_without[:win_rate]})"
      puts "Expectancy:    #{summary_without[:expectancy]}% → #{summary_with[:expectancy]}% (#{summary_with[:expectancy] - summary_without[:expectancy]})"
      puts "Total P&L:     #{summary_without[:total_pnl_percent]}% → #{summary_with[:total_pnl_percent]}% (#{summary_with[:total_pnl_percent] - summary_without[:total_pnl_percent]})"
      puts '=' * 80
    end
  end
end
