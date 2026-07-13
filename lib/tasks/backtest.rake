# lib/tasks/backtest.rake
# frozen_string_literal: true

# Wrapper class to adapt active strategies (BaseStrategy format) to BacktestService
class ActiveStrategyBacktestWrapper
  def initialize(series:, strategy_class:, strategy_params: {})
    @series = series
    @strategy_class = strategy_class
    @strategy_params = strategy_params
  end

  def generate_signal(index)
    return nil if index < 15 # Warmup period

    truncated_series = CandleSeries.new(symbol: @series.symbol, interval: @series.interval)
    @series.candles.first(index + 1).each { |c| truncated_series.add_candle(c) }

    context = Strategies::StrategyContext.new(
      instrument_key: @series.symbol,
      candles: ->(_tf) { truncated_series },
      indicators: nil,
      session: mock_session,
      position: mock_position,
      params: @strategy_params,
      clock: -> { truncated_series.candles.last.timestamp },
      config: {},
      logger: nil
    )

    strategy = @strategy_class.new(params: @strategy_params)
    signal = strategy.call(context)

    case signal
    when Signals::BuyCall
      { type: :ce, price: truncated_series.candles.last.close }
    when Signals::BuyPut
      { type: :pe, price: truncated_series.candles.last.close }
    end
  rescue StandardError
    nil
  end

  private

  def mock_session
    @mock_session ||= Object.new.tap do |o|
      def o.entry_allowed? = true
      def o.market_open? = true
      def o.seconds_until_close = 18_000
      def o.should_force_exit? = false
    end
  end

  def mock_position
    @mock_position ||= Object.new.tap do |o|
      def o.open? = false
    end
  end
end

namespace :backtest do
  # Ensure services are disabled during backtests
  task env: :environment do
    ENV['BACKTEST_MODE'] = '1'
  end

  desc 'Run backtest on an instrument'
  task :run, %i[symbol interval days] => %i[env environment] do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    interval = args[:interval] || '5'
    days = (args[:days] || '90').to_i

    puts "\n🔍 Running backtest..."
    puts "Symbol: #{symbol} | Interval: #{interval}min | Days: #{days}"

    result = BacktestService.run(
      symbol: symbol,
      interval: interval,
      days_back: days,
      strategy: SupertrendBacktestStrategy
    )

    result.print_summary
  end

  desc 'Run backtest on all indices'
  task :indices, %i[interval days] => %i[env environment] do |_t, args|
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
        strategy: SupertrendBacktestStrategy
      )

      result.print_summary
      sleep 2 # Rate limit protection
    end
  end

  desc 'Compare active strategies on an instrument'
  task :compare, %i[symbol days] => %i[env environment] do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    days = (args[:days] || '90').to_i

    puts "\n🔍 Comparing Active Strategies..."
    puts "Symbol: #{symbol} | Days: #{days}"

    # Load active strategies
    load Rails.root.join('strategies/supertrend_v1/strategy.rb').to_s
    load Rails.root.join('strategies/supertrend-adx/strategy.rb').to_s
    load Rails.root.join('strategies/vwap-reversal/strategy.rb').to_s

    strategies = {
      'SupertrendV1' => {
        class: SupertrendV1,
        interval: '1',
        params: { supertrend_period: 10, supertrend_multiplier: 2.0, adx_min: 20.0 }
      },
      'SupertrendAdxStrategy' => {
        class: SupertrendAdxStrategy,
        interval: '5',
        params: { supertrend_period: 10, supertrend_multiplier: 3.0, adx_threshold: 25, adx_period: 14 }
      },
      'VwapReversalStrategy' => {
        class: VwapReversalStrategy,
        interval: '3',
        params: { rsi_period: 14, rsi_oversold: 30, rsi_overbought: 70, vwap_band_pct: 0.5 }
      }
    }

    strategies.each do |name, details|
      puts "\n============================================================"
      puts "📊 Running #{name} on #{details[:interval]}m timeframe..."
      puts '--------------------------------------------------------------------------------'

      result = BacktestService.run(
        symbol: symbol,
        interval: details[:interval],
        days_back: days,
        strategy: lambda { |series|
          ActiveStrategyBacktestWrapper.new(
            series: series,
            strategy_class: details[:class],
            strategy_params: details[:params]
          )
        }
      )

      result.print_summary
    end

    puts "\n================================================================================"
    puts '📈 Comparison complete'
    puts '================================================================================'
  end

  desc 'Run comprehensive backtest on all indices and timeframes for active strategies'
  task :all_indices, [:days] => %i[env environment] do |_t, args|
    days = (args[:days] || '90').to_i
    symbols = %w[NIFTY BANKNIFTY SENSEX]
    all_results = []

    # Load active strategies
    load Rails.root.join('strategies/supertrend_v1/strategy.rb').to_s
    load Rails.root.join('strategies/supertrend-adx/strategy.rb').to_s
    load Rails.root.join('strategies/vwap-reversal/strategy.rb').to_s

    strategies = {
      'SupertrendV1' => {
        class: SupertrendV1,
        interval: '1',
        params: { supertrend_period: 10, supertrend_multiplier: 2.0, adx_min: 20.0 }
      },
      'SupertrendAdxStrategy' => {
        class: SupertrendAdxStrategy,
        interval: '5',
        params: { supertrend_period: 10, supertrend_multiplier: 3.0, adx_threshold: 25, adx_period: 14 }
      },
      'VwapReversalStrategy' => {
        class: VwapReversalStrategy,
        interval: '3',
        params: { rsi_period: 14, rsi_oversold: 30, rsi_overbought: 70, vwap_band_pct: 0.5 }
      }
    }

    puts "\n#{'=' * 100}"
    puts '🚀 COMPREHENSIVE BACKTEST: All Indices × Active Strategies'
    puts '=' * 100
    puts "Days: #{days} | Symbols: #{symbols.join(', ')}"
    puts '=' * 100

    symbols.each do |symbol|
      strategies.each do |strategy_name, details|
        puts "\n📊 #{symbol} | Strategy: #{strategy_name} | Interval: #{details[:interval]}m"
        puts '-' * 100

        begin
          result = BacktestService.run(
            symbol: symbol,
            interval: details[:interval],
            days_back: days,
            strategy: lambda { |series|
              ActiveStrategyBacktestWrapper.new(
                series: series,
                strategy_class: details[:class],
                strategy_params: details[:params]
              )
            }
          )

          summary = result.summary
          next if summary.empty?

          all_results << {
            symbol: symbol,
            interval: details[:interval],
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
          Rails.logger.error("[Backtest] Failed for #{symbol}/#{details[:interval]}min/#{strategy_name}: #{e.message}")
        end

        sleep 1 # Rate limit protection
      end
    end

    # Summary of best results
    puts "\n#{'=' * 100}"
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
    puts "\n#{'-' * 100}"
    puts '📊 Top 5 by Expectancy:'
    puts '-' * 100
    top_5 = all_results.sort_by { |r| -(r[:summary][:expectancy] || -999) }.first(5)
    top_5.each_with_index do |res, idx|
      puts "  #{idx + 1}. #{res[:symbol]} | #{res[:interval]}min | #{res[:strategy]}"
      puts "     Expectancy: #{res[:summary][:expectancy]}% | P&L: #{res[:summary][:total_pnl_percent]}% | Win Rate: #{res[:summary][:win_rate]}% | Trades: #{res[:summary][:total_trades]}"
    end

    puts "\n#{'=' * 100}"
    puts "✅ Completed #{all_results.size} successful backtests"
    puts '=' * 100
  end

  desc 'Export backtest results to CSV'
  task :export, %i[symbol interval days output] => %i[env environment] do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    interval = args[:interval] || '5'
    days = (args[:days] || '90').to_i
    output_file = args[:output] || "backtest_#{symbol}_#{Time.current.to_i}.csv"

    result = BacktestService.run(
      symbol: symbol,
      interval: interval,
      days_back: days,
      strategy: SupertrendBacktestStrategy
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
