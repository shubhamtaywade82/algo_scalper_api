# lib/tasks/backtest.rake
# frozen_string_literal: true

namespace :backtest do
  desc 'Run backtest on an instrument'
  task :run, %i[symbol interval days] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    interval = args[:interval] || '5'
    days = (args[:days] || '90').to_i

    puts "\n🔍 Running backtest..."
    puts "Symbol: #{symbol} | Interval: #{interval}min | Days: #{days}"

    result = BacktestService.run(
      symbol: symbol,
      interval: interval,
      days_back: days,
      strategy: SimpleMomentumStrategy
    )

    result.print_summary
  end

  desc 'Run backtest on all indices'
  task :indices, %i[interval days] => :environment do |_t, args|
    interval = args[:interval] || '5'
    days = (args[:days] || '90').to_i

    symbols = %w[NIFTY BANKNIFTY SENSEX]

    symbols.each do |symbol|
      puts "\n#{'=' * 60}"
      puts "Testing #{symbol}..."
      puts '=' * 60

      result = BacktestService.run(
        symbol: symbol,
        interval: interval,
        days_back: days,
        strategy: SimpleMomentumStrategy
      )

      result.print_summary
      sleep 2 # Rate limit protection
    end
  end

  # desc 'Compare both strategies (SimpleMomentum vs InsideBar)'
  # task :compare, %i[symbol interval days] => :environment do |_t, args|
  #   symbol = args[:symbol] || 'NIFTY'
  #   interval = args[:interval] || '5'
  #   days = (args[:days] || '90').to_i

  #   puts "\n🔍 Comparing Strategies..."
  #   puts "Symbol: #{symbol} | Interval: #{interval}min | Days: #{days}"
  #   puts "\n#{'=' * 80}"

  #   strategies = [
  #     { name: 'SimpleMomentumStrategy', class: SimpleMomentumStrategy },
  #     { name: 'InsideBarStrategy', class: InsideBarStrategy }
  #   ]

  #   results = {}

  #   strategies.each do |strategy_info|
  #     puts "\n📊 Running #{strategy_info[:name]}..."
  #     puts '-' * 80

  #     result = BacktestService.run(
  #       symbol: symbol,
  #       interval: interval,
  #       days_back: days,
  #       strategy: strategy_info[:class]
  #     )

  #     results[strategy_info[:name]] = result.summary
  #     result.print_summary
  #     sleep 1 # Rate limit protection
  #   end

  #   # Comparison summary
  #   puts "\n#{'=' * 80}"
  #   puts '📈 COMPARISON SUMMARY'
  #   puts '=' * 80

  #   strategies.each do |strategy_info|
  #     name = strategy_info[:name]
  #     summary = results[name]

  #     next if summary.empty?

  #     puts "\n#{name}:"
  #     puts "  Total Trades:    #{summary[:total_trades]}"
  #     puts "  Win Rate:        #{summary[:win_rate]}%"
  #     puts "  Total P&L:       #{'+' if summary[:total_pnl_percent].positive?}#{summary[:total_pnl_percent]}%"
  #     puts "  Expectancy:      #{'+' if summary[:expectancy].positive?}#{summary[:expectancy]}% per trade"
  #     puts "  Avg Win:         +#{summary[:avg_win_percent]}%"
  #     puts "  Avg Loss:        #{summary[:avg_loss_percent]}%"
  #   end

  #   # Winner determination
  #   if results.values.all?(&:empty?)
  #     puts "\n⚠️  No trades executed by either strategy"
  #   else
  #     winner = results.max_by { |_name, summary| summary[:expectancy] || -999 }
  #     puts "\n🏆 Best Strategy: #{winner[0]} (Expectancy: #{winner[1][:expectancy]}%)"
  #   end

  #   puts "\n#{'=' * 80}"
  # end

  desc 'Compare strategies on an instrument'
  task :compare, %i[symbol interval days] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    interval = args[:interval] || '5'
    days = (args[:days] || '90').to_i

    puts "\n🔍 Comparing Strategies..."
    puts "Symbol: #{symbol} | Interval: #{interval}min | Days: #{days}"

    strategies = {
      'SimpleMomentumStrategy' => ->(series) { SimpleMomentumStrategy.new(series: series) },
      'InsideBarStrategy' => ->(series) { InsideBarStrategy.new(series: series) },
      'SupertrendAdxStrategy' => lambda { |series|
        SupertrendAdxStrategy.new(
          series: series,
          supertrend_cfg: AlgoConfig.fetch.dig(:signals, :supertrend) || { period: 7, multiplier: 3 },
          adx_min_strength: AlgoConfig.fetch.dig(:signals, :adx, :min_strength) || 20
        )
      }
    }

    strategies.each do |name, strategy_lambda|
      puts "\n============================================================"
      puts "📊 Running #{name}..."
      puts '--------------------------------------------------------------------------------'

      result = BacktestService.run(
        symbol: symbol,
        interval: interval,
        days_back: days,
        strategy: strategy_lambda
      )

      result.print_summary
    end

    puts "\n================================================================================"
    puts '📈 Comparison complete'
    puts '================================================================================'
  end

  desc 'Run comprehensive backtest on all indices and timeframes'
  task :all_indices, [:days] => :environment do |_t, args|
    days = (args[:days] || '90').to_i
    symbols = %w[NIFTY BANKNIFTY SENSEX]
    intervals = %w[5 15]
    all_results = []

    strategies = {
      'SimpleMomentumStrategy' => ->(series) { SimpleMomentumStrategy.new(series: series) },
      'InsideBarStrategy' => ->(series) { InsideBarStrategy.new(series: series) },
      'SupertrendAdxStrategy' => lambda { |series|
        SupertrendAdxStrategy.new(
          series: series,
          supertrend_cfg: AlgoConfig.fetch.dig(:signals, :supertrend) || { period: 7, multiplier: 3 },
          adx_min_strength: AlgoConfig.fetch.dig(:signals, :adx, :min_strength) || 20
        )
      }
    }

    puts "\n" + ('=' * 100)
    puts '🚀 COMPREHENSIVE BACKTEST: All Indices × All Timeframes × All Strategies'
    puts '=' * 100
    puts "Days: #{days} | Symbols: #{symbols.join(', ')} | Intervals: #{intervals.join(', ')}min"
    puts '=' * 100

    symbols.each do |symbol|
      intervals.each do |interval|
        puts "\n" + ('=' * 100)
        puts "📊 #{symbol} - #{interval}min Timeframe"
        puts '=' * 100

        strategies.each do |strategy_name, strategy_lambda|
          puts "\n" + ('-' * 100)
          puts "  Strategy: #{strategy_name}"
          puts '-' * 100

          begin
            result = BacktestService.run(
              symbol: symbol,
              interval: interval,
              days_back: days,
              strategy: strategy_lambda
            )

            summary = result.summary
            next if summary.empty?

            all_results << {
              symbol: symbol,
              interval: interval,
              strategy: strategy_name,
              summary: summary
            }

            puts "  Total Trades:    #{summary[:total_trades]}"
            puts "  Win Rate:        #{summary[:win_rate]}%"
            puts "  Total P&L:       #{'+' if summary[:total_pnl_percent].positive?}#{summary[:total_pnl_percent]}%"
            puts "  Expectancy:      #{'+' if summary[:expectancy].positive?}#{summary[:expectancy]}% per trade"
            puts "  Avg Win:         +#{summary[:avg_win_percent]}%"
            puts "  Avg Loss:        #{summary[:avg_loss_percent]}%"
          rescue StandardError => e
            puts "  ❌ Error: #{e.message}"
            Rails.logger.error("[Backtest] Failed for #{symbol}/#{interval}min/#{strategy_name}: #{e.message}")
          end

          sleep 1 # Rate limit protection
        end
      end
    end

    # Summary of best results
    puts "\n" + ('=' * 100)
    puts '🏆 BEST RESULTS SUMMARY'
    puts '=' * 100

    if all_results.empty?
      puts "\n⚠️  No successful backtests completed"
      next
    end

    # Best by Expectancy
    best_expectancy = all_results.max_by { |r| r[:summary][:expectancy] || -999 }
    puts "\n📈 Best Expectancy:"
    puts "  #{best_expectancy[:symbol]} | #{best_expectancy[:interval]}min | #{best_expectancy[:strategy]}"
    puts "  Expectancy: #{best_expectancy[:summary][:expectancy]}% | Total P&L: #{best_expectancy[:summary][:total_pnl_percent]}% | Trades: #{best_expectancy[:summary][:total_trades]}"

    # Best by Total P&L
    best_pnl = all_results.max_by { |r| r[:summary][:total_pnl_percent] || -999 }
    puts "\n💰 Best Total P&L:"
    puts "  #{best_pnl[:symbol]} | #{best_pnl[:interval]}min | #{best_pnl[:strategy]}"
    puts "  Total P&L: #{best_pnl[:summary][:total_pnl_percent]}% | Expectancy: #{best_pnl[:summary][:expectancy]}% | Trades: #{best_pnl[:summary][:total_trades]}"

    # Best by Win Rate
    best_winrate = all_results.max_by { |r| r[:summary][:win_rate] || 0 }
    puts "\n🎯 Best Win Rate:"
    puts "  #{best_winrate[:symbol]} | #{best_winrate[:interval]}min | #{best_winrate[:strategy]}"
    puts "  Win Rate: #{best_winrate[:summary][:win_rate]}% | Expectancy: #{best_winrate[:summary][:expectancy]}% | Trades: #{best_winrate[:summary][:total_trades]}"

    # Top 5 by Expectancy
    puts "\n" + ('-' * 100)
    puts '📊 Top 5 by Expectancy:'
    puts '-' * 100
    top_5 = all_results.sort_by { |r| -(r[:summary][:expectancy] || -999) }.first(5)
    top_5.each_with_index do |result, idx|
      puts "  #{idx + 1}. #{result[:symbol]} | #{result[:interval]}min | #{result[:strategy]}"
      puts "     Expectancy: #{result[:summary][:expectancy]}% | P&L: #{result[:summary][:total_pnl_percent]}% | Win Rate: #{result[:summary][:win_rate]}% | Trades: #{result[:summary][:total_trades]}"
    end

    puts "\n" + ('=' * 100)
    puts "✅ Completed #{all_results.size} successful backtests"
    puts '=' * 100
  end

  desc 'Export backtest results to CSV'
  task :export, %i[symbol interval days output] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    interval = args[:interval] || '5'
    days = (args[:days] || '90').to_i
    output_file = args[:output] || "backtest_#{symbol}_#{Time.current.to_i}.csv"

    result = BacktestService.run(
      symbol: symbol,
      interval: interval,
      days_back: days,
      strategy: SimpleMomentumStrategy
    )

    summary = result.summary
    return puts 'No trades to export' if summary[:trades].blank?

    require 'csv'
    CSV.open(output_file, 'w') do |csv|
      # Headers
      csv << ['Signal Type', 'Entry Time', 'Entry Price', 'Exit Time', 'Exit Price', 'P&L %', 'Exit Reason', 'Bars Held']

      # Data
      summary[:trades].each do |trade|
        csv << [
          trade[:signal_type].to_s.upcase,
          trade[:entry_time],
          trade[:entry_price],
          trade[:exit_time],
          trade[:exit_price],
          trade[:pnl_percent],
          trade[:exit_reason],
          trade[:bars_held]
        ]
      end
    end

    puts "\n✅ Exported #{summary[:trades].size} trades to #{output_file}"
    result.print_summary
  end
end
