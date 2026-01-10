# frozen_string_literal: true

namespace :backtest do
  namespace :signal_generator do
    desc 'Backtest Signal Generator (Supertrend + ADX) for NIFTY and SENSEX'
    task :nifty_sensex, [:days_back] => :environment do |_t, args|
      days_back = (args[:days_back] || ENV['DAYS_BACK'] || '30').to_i

      puts "\n#{'=' * 100}"
      puts 'Signal Generator Backtest - NIFTY & SENSEX'
      puts '=' * 100
      puts "Lookback Period: #{days_back} days"
      puts 'Timeframes: 1m (execution), 5m (signals)'
      puts 'Indices: NIFTY, SENSEX'
      puts "#{'=' * 100}\n"

      indices = %w[NIFTY SENSEX]
      all_results = {}

      indices.each do |index_key|
        puts "\n#{'-' * 100}"
        puts "Backtesting Signal Generator for #{index_key}"
        puts '-' * 100

        begin
          # Use optimized parameters if available (pass nil to auto-load)
          result = Backtest::SignalGeneratorBacktester.run(
            symbol: index_key,
            interval_1m: '1',
            interval_5m: '5',
            days_back: days_back,
            supertrend_cfg: nil,  # nil = auto-load from BestIndicatorParam
            adx_min_strength: nil # nil = auto-load from BestIndicatorParam
          )

          summary = result.summary
          all_results[index_key] = summary

          puts "\n📊 Signal Generator Results for #{index_key}:"
          puts "   Total Signals: #{summary[:total_signals]}"
          puts "   Bullish: #{summary[:bullish_signals]} (#{summary[:bullish_pct]}%)"
          puts "   Bearish: #{summary[:bearish_signals]} (#{summary[:bearish_pct]}%)"
          puts "   Accuracy: #{summary[:accuracy_pct]}%"
          puts "   Profitable: #{summary[:profitable_signals]} | Losing: #{summary[:losing_signals]}"
          puts "   Avg Price Move: #{summary[:avg_price_move_pct]}%"
          puts "   Signals with Moves: #{summary[:signals_with_moves]} (#{summary[:signals_with_moves_pct]}%)"
        rescue StandardError => e
          puts "❌ ERROR: #{e.class} - #{e.message}"
          puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
          all_results[index_key] = { error: e.message }
        end

        puts "\n"
      end

      # Summary comparison
      puts "\n#{'=' * 100}"
      puts 'SIGNAL GENERATOR BACKTEST SUMMARY'
      puts '=' * 100

      indices.each do |index_key|
        result = all_results[index_key]
        next if result[:error]

        puts "\n📈 #{index_key}:"
        puts "   Signals: #{result[:total_signals]} | Accuracy: #{result[:accuracy_pct]}% | Avg Move: #{result[:avg_price_move_pct]}%"
      end

      puts "\n#{'=' * 100}"
      puts '✅ Backtest Complete!'
      puts '=' * 100
      puts "\n"
    end

    desc 'Backtest Signal Generator for single index'
    task :single, %i[index days_back] => :environment do |_t, args|
      index_key = args[:index] || ENV['INDEX'] || 'NIFTY'
      days_back = (args[:days_back] || ENV['DAYS_BACK'] || '30').to_i

      puts "\n#{'=' * 100}"
      puts "Signal Generator Backtest - #{index_key}"
      puts '=' * 100
      puts "Lookback Period: #{days_back} days"
      puts "#{'=' * 100}\n"

      # Use optimized parameters if available (pass nil to auto-load)
      result = Backtest::SignalGeneratorBacktester.run(
        symbol: index_key,
        interval_1m: '1',
        interval_5m: '5',
        days_back: days_back,
        supertrend_cfg: nil,  # nil = auto-load from BestIndicatorParam
        adx_min_strength: nil # nil = auto-load from BestIndicatorParam
      )

      result.print_summary

      puts "\n#{'=' * 100}"
      puts '✅ Backtest Complete!'
      puts '=' * 100
      puts "\n"
    end
  end
end
