# frozen_string_literal: true

namespace :optimization do
  desc 'Run parameter optimization for NIFTY and SENSEX'
  task :nifty_sensex, %i[interval lookback_days] => :environment do |_t, args|
    interval = args[:interval] || ENV['INTERVAL'] || '5'
    lookback_days = (args[:lookback_days] || ENV['LOOKBACK_DAYS'] || '45').to_i

    puts "\n" + ('=' * 80)
    puts 'Indicator Parameter Optimization - NIFTY & SENSEX'
    puts '=' * 80
    puts "Interval: #{interval}m"
    puts "Lookback: #{lookback_days} days"
    puts ('=' * 80) + "\n"

    # Check if table exists
    unless BestIndicatorParam.table_exists?
      puts "\n❌ ERROR: best_indicator_params table does not exist!"
      puts "\nPlease run the migration first:"
      puts '  rails db:migrate'
      exit 1
    end

    # Get index configurations
    algo_config = AlgoConfig.fetch
    nifty_cfg = algo_config[:indices]&.find { |i| i[:key] == 'NIFTY' }
    sensex_cfg = algo_config[:indices]&.find { |i| i[:key] == 'SENSEX' }

    unless nifty_cfg
      puts '❌ ERROR: NIFTY configuration not found in algo.yml'
      exit 1
    end

    unless sensex_cfg
      puts '⚠️  WARNING: SENSEX configuration not found in algo.yml'
      puts '   Continuing with NIFTY only...'
    end

    # Helper to run optimization
    def run_optimization(index_name, index_cfg, interval, lookback_days)
      puts "\n" + ('-' * 80)
      puts "Optimizing #{index_name} (#{interval}m, #{lookback_days} days)"
      puts '-' * 80

      begin
        # Get instrument
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)

        unless instrument
          puts "❌ Failed to get instrument for #{index_name}"
          return nil
        end

        puts "📊 Instrument: #{instrument.symbol_name} (SID: #{instrument.security_id})"
        puts '🔄 Starting optimization...'
        $stdout.flush

        # Test data fetch first
        puts '   Testing data fetch...'
        $stdout.flush
        test_data = instrument.intraday_ohlc(interval: interval, days: lookback_days)
        if test_data.nil? || test_data.empty?
          puts '   ❌ No data returned from API'
          return nil
        end
        puts "   ✅ Data fetch successful (#{test_data.is_a?(Hash) ? test_data.keys.size : test_data.size} records)"
        $stdout.flush

        start_time = Time.current

        # Run optimization
        puts '   Creating optimizer...'
        $stdout.flush
        optimizer = Optimization::IndicatorOptimizer.new(
          instrument: instrument,
          interval: interval,
          lookback_days: lookback_days
        )
        puts '   Running optimization (this may take several minutes)...'
        $stdout.flush

        result = optimizer.run

        elapsed = Time.current - start_time

        if result[:error]
          puts "❌ Optimization failed: #{result[:error]}"
          return nil
        end

        unless result[:score] && result[:params] && result[:metrics]
          puts '❌ No valid results returned'
          return nil
        end

        # Display results
        puts "\n✅ Optimization Complete (#{elapsed.round(2)}s)"
        puts "\n📈 Best Parameters:"
        puts "   Sharpe Ratio: #{result[:score].round(4)}"
        puts "   Win Rate: #{(result[:metrics][:win_rate] * 100).round(2)}%"
        puts "   Expectancy: #{result[:metrics][:expectancy].round(4)}"
        puts "   Net PnL: #{result[:metrics][:net_pnl].round(2)}"
        puts "   Avg Move: #{result[:metrics][:avg_move].round(4)}%"

        puts "\n⚙️  Parameter Values:"
        result[:params].each do |key, value|
          puts "   #{key}: #{value}"
        end

        # Check if saved to database
        best = BestIndicatorParam.best_for(instrument.id, interval).first
        if best
          puts "\n💾 Saved to database:"
          puts "   Score: #{best.score.round(4)}"
          puts "   Updated: #{best.updated_at}"
        end

        result
      rescue StandardError => e
        puts "❌ ERROR: #{e.class} - #{e.message}"
        puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
        nil
      end
    end

    # Run optimizations
    results = {}

    # Optimize NIFTY
    results[:nifty] = run_optimization('NIFTY', nifty_cfg, interval, lookback_days) if nifty_cfg

    # Optimize SENSEX
    results[:sensex] = run_optimization('SENSEX', sensex_cfg, interval, lookback_days) if sensex_cfg

    # Summary
    puts "\n" + ('=' * 80)
    puts 'OPTIMIZATION SUMMARY'
    puts '=' * 80

    if results[:nifty]
      puts "\n📊 NIFTY (#{interval}m):"
      puts "   Sharpe: #{results[:nifty][:score]&.round(4)}"
      puts "   Win Rate: #{(results[:nifty][:metrics][:win_rate] * 100).round(2)}%"
      puts "   ADX Threshold: #{results[:nifty][:params][:adx_thresh]}"
      puts "   RSI Lo/Hi: #{results[:nifty][:params][:rsi_lo]}/#{results[:nifty][:params][:rsi_hi]}"
    else
      puts "\n❌ NIFTY: Optimization failed"
    end

    if results[:sensex]
      puts "\n📊 SENSEX (#{interval}m):"
      puts "   Sharpe: #{results[:sensex][:score]&.round(4)}"
      puts "   Win Rate: #{(results[:sensex][:metrics][:win_rate] * 100).round(2)}%"
      puts "   ADX Threshold: #{results[:sensex][:params][:adx_thresh]}"
      puts "   RSI Lo/Hi: #{results[:sensex][:params][:rsi_lo]}/#{results[:sensex][:params][:rsi_hi]}"
    else
      puts "\n❌ SENSEX: Optimization failed or not configured"
    end

    puts "\n" + ('=' * 80)
    puts '✅ Done! Results saved to best_indicator_params table'
    puts '=' * 80
    puts "\nTo retrieve optimized parameters:"
    puts "  best = BestIndicatorParam.best_for(instrument.id, '#{interval}').first"
    puts '  params = best.params'
    puts "\n"
  end

  desc 'Run single indicator optimization (recommended - faster)'
  task :single_indicator, %i[index interval lookback_days] => :environment do |_t, args|
    index_key = args[:index] || ENV['INDEX'] || 'NIFTY'
    interval = args[:interval] || ENV['INTERVAL'] || '5'
    lookback_days = (args[:lookback_days] || ENV['LOOKBACK_DAYS'] || '30').to_i

    puts "\n" + ('=' * 80)
    puts 'Single Indicator Parameter Optimization'
    puts '=' * 80
    puts "Index: #{index_key}"
    puts "Interval: #{interval}m"
    puts "Lookback: #{lookback_days} days"
    puts ('=' * 80) + "\n"

    # Check if table exists
    unless BestIndicatorParam.table_exists?
      puts "\n❌ ERROR: best_indicator_params table does not exist!"
      puts "\nPlease run the migration first:"
      puts '  rails db:migrate'
      exit 1
    end

    # Get index configuration
    algo_config = AlgoConfig.fetch
    index_cfg = algo_config[:indices]&.find { |i| i[:key] == index_key }

    unless index_cfg
      puts "❌ ERROR: #{index_key} configuration not found in algo.yml"
      exit 1
    end

    begin
      # Get instrument
      instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)

      unless instrument
        puts "❌ Failed to get instrument for #{index_key}"
        exit 1
      end

      puts "📊 Instrument: #{instrument.symbol_name} (SID: #{instrument.security_id})\n\n"

      # Optimize each indicator separately
      indicators = %i[adx rsi macd supertrend]
      results = {}

      indicators.each do |indicator|
        puts '-' * 80
        puts "Optimizing #{indicator.to_s.upcase} (#{interval}m, #{lookback_days} days)"
        puts '-' * 80

        begin
          start_time = Time.current

          optimizer = Optimization::SingleIndicatorOptimizer.new(
            instrument: instrument,
            interval: interval,
            lookback_days: lookback_days,
            indicator: indicator
          )

          result = optimizer.run

          elapsed = Time.current - start_time

          if result[:error]
            puts "❌ Optimization failed: #{result[:error]}"
            results[indicator] = nil
            next
          end

          unless result[:score] && result[:params] && result[:metrics]
            puts "❌ No valid results returned"
            results[indicator] = nil
            next
          end

          # Display results
          puts "\n✅ Optimization Complete (#{elapsed.round(2)}s)"
          puts "\n📈 Best Parameters:"
          puts "   Average Price Move: #{result[:score].round(4)}%"
          puts "   Total Signals: #{result[:metrics][:total_signals]}"
          puts "   Win Rate: #{(result[:metrics][:win_rate] * 100).round(2)}%"
          puts "   Max Move: #{result[:metrics][:max_move_pct]&.round(4)}%"

          puts "\n⚙️  Parameter Values:"
          result[:params].each do |key, value|
            puts "   #{key}: #{value}"
          end

          results[indicator] = result
        rescue StandardError => e
          puts "❌ ERROR: #{e.class} - #{e.message}"
          puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
          results[indicator] = nil
        end

        puts "\n"
      end

      # Summary
      puts '=' * 80
      puts 'OPTIMIZATION SUMMARY'
      puts '=' * 80

      indicators.each do |indicator|
        if results[indicator]
          result = results[indicator]
          puts "\n📊 #{indicator.to_s.upcase}:"
          puts "   Avg Price Move: #{result[:score]&.round(4)}%"
          puts "   Signals: #{result[:metrics][:total_signals]}"
          puts "   Win Rate: #{(result[:metrics][:win_rate] * 100).round(2)}%" if result[:metrics][:win_rate]
          puts "   Max Move: #{result[:metrics][:max_move_pct]&.round(4)}%" if result[:metrics][:max_move_pct]
          puts "   Best Params: #{result[:params].inspect}"
        else
          puts "\n❌ #{indicator.to_s.upcase}: Optimization failed"
        end
      end

      puts "\n" + '=' * 80
      puts '✅ Done! Results saved to best_indicator_params table'
      puts '=' * 80
      puts "\nTo retrieve optimized parameters:"
      puts "  best = BestIndicatorParam.best_for_indicator(instrument.id, '#{interval}', 'adx').first"
      puts '  params = best.params'
      puts "\n"
    rescue StandardError => e
      puts "❌ ERROR: #{e.class} - #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
      exit 1
    end
  end

  desc 'Run single indicator optimization for all timeframes'
  task :all_timeframes, %i[index lookback_days] => :environment do |_t, args|
    index_key = args[:index] || ENV['INDEX'] || 'NIFTY'
    lookback_days = (args[:lookback_days] || ENV['LOOKBACK_DAYS'] || '45').to_i

    puts "\n" + ('=' * 80)
    puts 'Single Indicator Optimization - All Timeframes'
    puts '=' * 80
    puts "Index: #{index_key}"
    puts "Lookback: #{lookback_days} days"
    puts "Timeframes: 1m, 5m, 15m"
    puts ('=' * 80) + "\n"

    # Check if table exists
    unless BestIndicatorParam.table_exists?
      puts "\n❌ ERROR: best_indicator_params table does not exist!"
      puts "\nPlease run the migration first:"
      puts '  rails db:migrate'
      exit 1
    end

    # Get index configuration
    algo_config = AlgoConfig.fetch
    index_cfg = algo_config[:indices]&.find { |i| i[:key] == index_key }

    unless index_cfg
      puts "❌ ERROR: #{index_key} configuration not found in algo.yml"
      exit 1
    end

    begin
      # Get instrument
      instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)

      unless instrument
        puts "❌ Failed to get instrument for #{index_key}"
        exit 1
      end

      puts "📊 Instrument: #{instrument.symbol_name} (SID: #{instrument.security_id})"

      intervals = %w[1 5 15]
      indicators = %i[adx rsi macd supertrend]
      all_results = {}

      intervals.each do |interval|
        puts "\n" + ('-' * 80)
        puts "Optimizing #{interval}m timeframe..."
        puts '-' * 80

        interval_results = {}

        indicators.each do |indicator|
          puts "\n  Optimizing #{indicator.to_s.upcase}..."
          begin
            optimizer = Optimization::SingleIndicatorOptimizer.new(
              instrument: instrument,
              interval: interval,
              lookback_days: lookback_days,
              indicator: indicator
            )

            result = optimizer.run
            interval_results[indicator] = result

            if result[:error]
              puts "    ❌ Failed: #{result[:error]}"
            else
              puts "    ✅ Complete - Avg Move: #{result[:score]&.round(4)}%"
            end
          rescue StandardError => e
            puts "    ❌ ERROR: #{e.message}"
            interval_results[indicator] = { error: e.message }
          end
        end

        all_results[interval] = interval_results
      end

      puts "\n" + ('=' * 80)
      puts 'OPTIMIZATION SUMMARY'
      puts '=' * 80

      intervals.each do |interval|
        interval_results = all_results[interval]
        puts "\n📊 #{interval}m:"

        indicators.each do |indicator|
          result = interval_results[indicator]
          if result && !result[:error] && result[:score]
            puts "   #{indicator.to_s.upcase}: Avg Move #{result[:score].round(4)}% (#{result[:metrics][:total_signals]} signals)"
          else
            puts "   #{indicator.to_s.upcase}: ❌ Failed"
          end
        end
      end

      puts "\n" + ('=' * 80)
      puts '✅ Done! Results saved to best_indicator_params table'
      puts '=' * 80
      puts "\n"
    rescue StandardError => e
      puts "❌ ERROR: #{e.class} - #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
      exit 1
    end
  end
end

