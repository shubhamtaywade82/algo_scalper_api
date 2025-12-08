# frozen_string_literal: true

namespace :backtest do
  namespace :no_trade_engine do
    desc 'Backtest NoTradeEngine for NIFTY and SENSEX on 1m and 5m (intraday)'
    task :nifty_sensex_intraday, [:days_back] => :environment do |_t, args|
      days_back = (args[:days_back] || ENV['DAYS_BACK'] || '30').to_i

      puts "\n" + ('=' * 100)
      puts 'NoTradeEngine Backtest - NIFTY & SENSEX (Intraday)'
      puts '=' * 100
      puts "Lookback Period: #{days_back} days"
      puts "Timeframes: 1m and 5m"
      puts "Indices: NIFTY, SENSEX"
      puts ('=' * 100) + "\n"

      indices = %w[NIFTY SENSEX]
      timeframes = %w[1 5]
      all_results = {}

      indices.each do |index_key|
        all_results[index_key] = {}

        timeframes.each do |timeframe|
          puts "\n" + ('-' * 100)
          puts "Backtesting #{index_key} @ #{timeframe}m (Intraday)"
          puts '-' * 100

          begin
            # For intraday backtesting:
            # - Always fetch 1m for precise entry/exit timing
            # - Always fetch 5m separately from API for ADX/DI calculations (never build from 1m)
            # - Signal generation uses the specified timeframe (1m or 5m)
            interval_1m = '1'
            interval_5m = '5'  # Always fetch 5m separately from API for ADX calculations

            # Use optimized parameters if available (pass nil to auto-load)
            result = BacktestServiceWithNoTradeEngine.run(
              symbol: index_key,
              interval_1m: interval_1m,
              interval_5m: interval_5m,
              days_back: days_back,
              supertrend_cfg: nil,  # nil = auto-load from BestIndicatorParam
              adx_min_strength: nil  # nil = auto-load from BestIndicatorParam (0 = let NoTradeEngine handle)
            )

            summary = result.summary
            all_results[index_key][timeframe] = {
              summary: summary,
              no_trade_stats: result.no_trade_stats
            }

            puts "\n📊 Results for #{index_key} @ #{timeframe}m:"
            puts "   Total Trades: #{summary[:total_trades]}"
            puts "   Win Rate: #{summary[:win_rate]&.round(2)}%"
            puts "   Total P&L: #{summary[:total_pnl_percent]&.round(2)}%"
            puts "   Expectancy: #{summary[:expectancy]&.round(2)}% per trade"
            puts "   Avg Win: +#{summary[:avg_win_percent]&.round(2)}%"
            puts "   Avg Loss: #{summary[:avg_loss_percent]&.round(2)}%"
            puts "   Max Drawdown: #{summary[:max_drawdown]&.round(2)}%"
            puts "\n🚫 NoTradeEngine Stats:"
            puts "   Phase 1 Blocked: #{result.no_trade_stats[:phase1_blocked]}"
            puts "   Phase 2 Blocked: #{result.no_trade_stats[:phase2_blocked]}"
            puts "   Signals Generated: #{result.no_trade_stats[:signal_generated]}"
            puts "   Trades Executed: #{result.no_trade_stats[:trades_executed]}"
            puts "   Block Rate: #{Backtest::NoTradeEngineHelper.calculate_block_rate(result.no_trade_stats)}%"

            if result.no_trade_stats[:phase2_reasons].any?
              puts "\n   Top Phase 2 Block Reasons:"
              result.no_trade_stats[:phase2_reasons]
                .sort_by { |_k, v| -v }
                .first(5)
                .each do |reason, count|
                  puts "     - #{reason}: #{count}"
                end
            end

          rescue StandardError => e
            puts "❌ ERROR: #{e.class} - #{e.message}"
            puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
            all_results[index_key][timeframe] = { error: e.message }
          end

          puts "\n"
        end
      end

      # Summary comparison
      puts "\n" + ('=' * 100)
      puts 'BACKTEST SUMMARY - NoTradeEngine Performance'
      puts '=' * 100

      indices.each do |index_key|
        puts "\n📈 #{index_key}:"
        timeframes.each do |timeframe|
          result = all_results[index_key][timeframe]
          next if result[:error]

          summary = result[:summary]
          stats = result[:no_trade_stats]
          next unless summary && summary[:total_trades]&.positive?

          puts "\n   #{timeframe}m Timeframe:"
          puts "      Trades: #{summary[:total_trades]} | Win Rate: #{summary[:win_rate]&.round(2)}% | P&L: #{summary[:total_pnl_percent]&.round(2)}%"
          puts "      Block Rate: #{Backtest::NoTradeEngineHelper.calculate_block_rate(stats)}% | Signals: #{stats[:signal_generated]} | Executed: #{stats[:trades_executed]}"
        end
      end

      # Best performing combination
      best = Backtest::NoTradeEngineHelper.find_best_performer(all_results)
      if best
        puts "\n🏆 Best Performing Combination:"
        puts "   #{best[:index]} @ #{best[:timeframe]}m"
        puts "   Win Rate: #{best[:win_rate]&.round(2)}% | P&L: #{best[:pnl]&.round(2)}% | Expectancy: #{best[:expectancy]&.round(2)}%"
      end

      puts "\n" + ('=' * 100)
      puts '✅ Backtest Complete!'
      puts '=' * 100
      puts "\n"
    end

    desc 'Backtest NoTradeEngine for single index and timeframe'
    task :single, %i[index timeframe days_back] => :environment do |_t, args|
      index_key = args[:index] || ENV['INDEX'] || 'NIFTY'
      timeframe = args[:timeframe] || ENV['TIMEFRAME'] || '5'
      days_back = (args[:days_back] || ENV['DAYS_BACK'] || '30').to_i

      puts "\n" + ('=' * 100)
      puts "NoTradeEngine Backtest - #{index_key} @ #{timeframe}m"
      puts '=' * 100
      puts "Lookback Period: #{days_back} days"
      puts ('=' * 100) + "\n"

      interval_1m = '1'
      interval_5m = '5'  # Always fetch 5m separately from API for ADX calculations

      # Use optimized parameters if available (pass nil to auto-load)
      result = BacktestServiceWithNoTradeEngine.run(
        symbol: index_key,
        interval_1m: interval_1m,
        interval_5m: interval_5m,
        days_back: days_back,
        supertrend_cfg: nil,  # nil = auto-load from BestIndicatorParam
        adx_min_strength: nil # nil = auto-load from BestIndicatorParam
      )

      result.print_summary

      puts "\n🚫 NoTradeEngine Detailed Stats:"
      puts "   Phase 1 Blocked: #{result.no_trade_stats[:phase1_blocked]}"
      puts "   Phase 2 Blocked: #{result.no_trade_stats[:phase2_blocked]}"
      puts "   Signals Generated: #{result.no_trade_stats[:signal_generated]}"
      puts "   Trades Executed: #{result.no_trade_stats[:trades_executed]}"
      puts "   Block Rate: #{Backtest::NoTradeEngineHelper.calculate_block_rate(result.no_trade_stats)}%"

      if result.no_trade_stats[:phase1_reasons].any?
        puts "\n   Phase 1 Block Reasons:"
        result.no_trade_stats[:phase1_reasons]
          .sort_by { |_k, v| -v }
          .each { |reason, count| puts "     - #{reason}: #{count}" }
      end

      if result.no_trade_stats[:phase2_reasons].any?
        puts "\n   Phase 2 Block Reasons:"
        result.no_trade_stats[:phase2_reasons]
          .sort_by { |_k, v| -v }
          .first(10)
          .each { |reason, count| puts "     - #{reason}: #{count}" }
      end

      puts "\n" + ('=' * 100)
      puts '✅ Backtest Complete!'
      puts '=' * 100
      puts "\n"
    end

  end
end

# Helper module for backtest tasks
module Backtest
  module NoTradeEngineHelper
    def self.calculate_block_rate(stats)
      total_checks = stats[:signal_generated] + stats[:phase1_blocked]
      return 0.0 if total_checks.zero?

      total_blocked = stats[:phase1_blocked] + stats[:phase2_blocked]
      (total_blocked.to_f / total_checks * 100).round(2)
    end

    def self.find_best_performer(all_results)
      best = nil
      best_score = -Float::INFINITY

      all_results.each do |index_key, timeframes|
        timeframes.each do |timeframe, result|
          next if result[:error]

          summary = result[:summary]
          next unless summary && summary[:total_trades]&.positive?

          # Score based on expectancy and win rate
          score = (summary[:expectancy] || 0) * 0.6 + (summary[:win_rate] || 0) * 0.4

          next unless score > best_score

          best_score = score
          best = {
            index: index_key,
            timeframe: timeframe,
            win_rate: summary[:win_rate],
            pnl: summary[:total_pnl_percent],
            expectancy: summary[:expectancy],
            trades: summary[:total_trades]
          }
        end
      end

      best
    end
  end
end
