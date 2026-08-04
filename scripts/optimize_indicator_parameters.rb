# frozen_string_literal: true

# Parameter Optimization Script for Indicators
# Tests different parameter combinations to find optimal settings for each index
# Usage: rails runner scripts/optimize_indicator_parameters.rb [INDEX] [DAYS] [INTERVAL]
# Example: rails runner scripts/optimize_indicator_parameters.rb NIFTY 30 1

# Disable trading services and WebSocket connections during optimization
ENV['SCRIPT_MODE'] = '1'
ENV['DISABLE_TRADING_SERVICES'] = '1'
ENV['BACKTEST_MODE'] = '1'

require 'csv'

class IndicatorParameterOptimizer
  def initialize(index_key:, days_back: 30, interval: '1')
    @index_key = index_key
    @days_back = days_back.to_i
    @interval = interval
    @results = []

    # Get index config
    indices = AlgoConfig.fetch[:indices] || []
    @index_cfg = indices.find { |idx| idx[:key] == index_key }
    raise "Index #{index_key} not found in config" unless @index_cfg

    # Get instrument
    @instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
    raise "Instrument not found for #{index_key}" unless @instrument
  end

  def run
    puts "\n#{'=' * 100}"
    puts 'INDICATOR PARAMETER OPTIMIZATION'
    puts '=' * 100
    puts "Index: #{@index_key}"
    puts "Days: #{@days_back}"
    puts "Interval: #{@interval}min"
    puts "#{'=' * 100}\n"

    # Fetch historical data
    puts '📊 Fetching historical data...'
    series = fetch_historical_data
    return unless series&.candles&.any?

    puts "✅ Loaded #{series.candles.size} candles\n"

    # Define parameter ranges to test
    parameter_sets = generate_parameter_combinations

    puts "🔍 Testing #{parameter_sets.size} parameter combinations..."
    puts "   (Processing #{series.candles.size} candles per combination)"
    puts "   Estimated time: ~#{(parameter_sets.size * 0.5 / 60).round(1)} minutes"
    puts "#{'-' * 100}\n"

    # Test each parameter combination
    start_time = Time.current
    parameter_sets.each_with_index do |params, idx|
      print "[#{idx + 1}/#{parameter_sets.size}] #{format_params(params)}... "
      $stdout.flush

      test_start = Time.current
      result = backtest_parameters(series, params)
      test_duration = Time.current - test_start

      if result
        @results << result.merge(params)
        elapsed = Time.current - start_time
        avg_time = elapsed / (idx + 1)
        remaining = avg_time * (parameter_sets.size - idx - 1)

        puts "✅ PnL: #{result[:total_pnl_pct].round(2)}% | " \
             "WR: #{result[:win_rate].round(1)}% | " \
             "Trades: #{result[:total_trades]} | " \
             "PF: #{result[:profit_factor].round(2)} | " \
             "[#{test_duration.round(1)}s, ETA: #{(remaining / 60).round(1)}min]"
      else
        puts "❌ No trades [#{test_duration.round(1)}s]"
      end
      $stdout.flush
    end

    # Analyze and display results
    analyze_results
  end

  private

  def fetch_historical_data
    to_date = Time.zone.today - 1.day
    from_date = to_date - @days_back.days

    ohlc_data = @instrument.intraday_ohlc(
      interval: @interval,
      from_date: from_date.to_s,
      to_date: to_date.to_s,
      days: @days_back
    )

    return nil if ohlc_data.blank?

    series = CandleSeries.new(symbol: @index_key, interval: @interval)
    series.load_from_raw(ohlc_data)
    series
  rescue StandardError => e
    puts "❌ Error fetching data: #{e.message}"
    nil
  end

  def generate_parameter_combinations
    combinations = []

    # Supertrend parameters
    supertrend_periods = [5, 7, 10, 14]
    supertrend_multipliers = [2.0, 2.5, 3.0, 3.5, 4.0]

    # ADX parameters
    adx_periods = [10, 14, 18]
    adx_1m_thresholds = [12, 14, 16, 18, 20]
    adx_5m_thresholds = [10, 12, 14, 16, 18, 20]

    # RSI parameters (if using RSI filter) - TODO: Add RSI optimization
    # rsi_periods = [10, 14, 21]
    # rsi_overbought = [65, 70, 75]
    # rsi_oversold = [25, 30, 35]

    # MACD parameters (if using MACD filter) - TODO: Add MACD optimization
    # macd_fast = [8, 12, 16]
    # macd_slow = [21, 26, 31]
    # macd_signal = [7, 9, 11]

    # Generate combinations (using grid search with reasonable limits)
    # Focus on Supertrend + ADX first (most important)
    supertrend_periods.each do |st_period|
      supertrend_multipliers.each do |st_mult|
        adx_periods.each do |adx_period|
          adx_1m_thresholds.each do |adx_1m|
            adx_5m_thresholds.each do |adx_5m|
              combinations << {
                supertrend_period: st_period,
                supertrend_multiplier: st_mult,
                adx_period: adx_period,
                adx_1m_threshold: adx_1m,
                adx_5m_threshold: adx_5m
              }
            end
          end
        end
      end
    end

    # Limit to reasonable number of tests (can be increased)
    combinations.first(500) # Test first 500 combinations
  end

  def backtest_parameters(series, params)
    # Simulate trading with given parameters
    trades = []
    position = nil
    entry_price = nil
    entry_index = nil

    # Need enough candles for indicators
    min_candles = [params[:supertrend_period], params[:adx_period], 50].max
    return nil if series.candles.size < min_candles

    # Pre-calculate Supertrend for entire series (much faster than recalculating per candle)
    begin
      st_cfg = {
        period: params[:supertrend_period],
        base_multiplier: params[:supertrend_multiplier]
      }
      st_result = Indicators::Supertrend.new(series: series, **st_cfg).call
      return nil unless st_result && st_result[:line]

      supertrend_line = st_result[:line]
      closes = series.closes
    rescue StandardError => e
      return nil
    end

    # Pre-calculate ADX values (cache for performance)
    # Note: ADX needs to be calculated on partial series for accuracy
    # For optimization speed, we'll calculate at intervals and interpolate
    adx_values = Array.new(series.candles.size, nil)
    adx_period = params[:adx_period]

    # Calculate ADX at intervals (trade-off between speed and accuracy)
    # For large datasets, calculate ADX every Nth candle to speed up
    adx_calc_step = if series.candles.size > 10_000
                      20
                    else
                      (series.candles.size > 5000 ? 10 : 5)
                    end
    adx_calc_count = ((series.candles.size - min_candles) / adx_calc_step).to_i

    adx_calc_idx = 0
    (min_candles...series.candles.size).step(adx_calc_step) do |i|
      adx_calc_idx += 1
      if adx_calc_count > 50 && (adx_calc_idx % 50).zero?
        print 'A' # Show ADX calculation progress
        $stdout.flush
      end

      partial_series = create_partial_series(series, i)
      next unless partial_series

      begin
        adx_val = partial_series.adx(adx_period)
        # Fill in the step range with this value (simplified interpolation)
        adx_calc_step.times do |offset|
          idx = i + offset
          break if idx >= series.candles.size

          adx_values[idx] = adx_val if adx_val
        end
      rescue StandardError
        next
      end
    end
    print ' ' if adx_calc_count > 50 # Space after ADX progress
    $stdout.flush

    # Use a step size to speed up backtesting (process every Nth candle)
    # This reduces accuracy but significantly speeds up optimization
    step_size = series.candles.size > 5000 ? 3 : 1 # Step by 3 for large datasets

    total_iterations = ((series.candles.size - min_candles) / step_size).to_i
    processed = 0

    (min_candles...series.candles.size).step(step_size) do |i|
      processed += 1

      # Show progress every 500 iterations for long backtests
      if total_iterations > 500 && (processed % 500).zero?
        print '.'
        $stdout.flush
      end

      # Get pre-calculated values
      adx_1m = adx_values[i]
      next unless adx_1m && adx_1m >= params[:adx_1m_threshold]

      # Determine trend from supertrend line
      st_line_val = supertrend_line[i]
      current_close = closes[i]
      next unless st_line_val && current_close

      current_trend = current_close >= st_line_val ? :bullish : :bearish
      current_price = current_close

      # Entry logic
      if position.nil?
        # Check for entry signal
        if current_trend == :bullish && adx_1m >= params[:adx_1m_threshold]
          position = :long
          entry_price = current_price
          entry_index = i
        elsif current_trend == :bearish && adx_1m >= params[:adx_1m_threshold]
          position = :short
          entry_price = current_price
          entry_index = i
        end
      else
        # Exit logic (simple: exit on trend reversal or fixed stop/target)
        should_exit = false
        exit_reason = nil

        if position == :long
          if current_trend == :bearish
            should_exit = true
            exit_reason = 'trend_reversal'
          elsif current_price <= entry_price * 0.93 # 7% stop loss
            should_exit = true
            exit_reason = 'stop_loss'
          elsif current_price >= entry_price * 1.15 # 15% take profit
            should_exit = true
            exit_reason = 'take_profit'
          end
        elsif position == :short
          if current_trend == :bullish
            should_exit = true
            exit_reason = 'trend_reversal'
          elsif current_price >= entry_price * 1.07 # 7% stop loss
            should_exit = true
            exit_reason = 'stop_loss'
          elsif current_price <= entry_price * 0.85 # 15% take profit
            should_exit = true
            exit_reason = 'take_profit'
          end
        end

        if should_exit
          pnl_pct = if position == :long
                      ((current_price - entry_price) / entry_price * 100.0)
                    else
                      ((entry_price - current_price) / entry_price * 100.0)
                    end

          trades << {
            entry_index: entry_index,
            exit_index: i,
            entry_price: entry_price,
            exit_price: current_price,
            direction: position,
            pnl_pct: pnl_pct,
            exit_reason: exit_reason
          }

          position = nil
          entry_price = nil
          entry_index = nil
        end
      end
    end

    # Close any open position at end
    if position && entry_price
      final_price = series.candles.last.close
      pnl_pct = if position == :long
                  ((final_price - entry_price) / entry_price * 100.0)
                else
                  ((entry_price - final_price) / entry_price * 100.0)
                end

      trades << {
        entry_index: entry_index,
        exit_index: series.candles.size - 1,
        entry_price: entry_price,
        exit_price: final_price,
        direction: position,
        pnl_pct: pnl_pct,
        exit_reason: 'end_of_data'
      }
    end

    return nil if trades.empty?

    # Calculate metrics
    calculate_metrics(trades)
  rescue StandardError => e
    Rails.logger.error("[Optimizer] Backtest failed: #{e.message}") if defined?(Rails)
    nil
  ensure
    # Clear progress dots if any
    print "\n" if total_iterations > 1000 && processed.positive?
    $stdout.flush
  end

  def create_partial_series(full_series, end_index)
    partial = CandleSeries.new(symbol: @index_key, interval: @interval)
    partial.candles.concat(full_series.candles[0..end_index])
    partial
  end

  def calculate_metrics(trades)
    total_trades = trades.size
    winning_trades = trades.select { |t| t[:pnl_pct].positive? }
    losing_trades = trades.select { |t| t[:pnl_pct].negative? }

    win_rate = total_trades.positive? ? (winning_trades.size.to_f / total_trades * 100.0) : 0.0

    total_pnl_pct = trades.sum { |t| t[:pnl_pct] }
    avg_win = winning_trades.any? ? winning_trades.sum { |t| t[:pnl_pct] } / winning_trades.size : 0.0
    avg_loss = losing_trades.any? ? losing_trades.sum { |t| t[:pnl_pct] } / losing_trades.size : 0.0

    profit_factor = if avg_loss.abs > 0.001
                      (avg_win * winning_trades.size) / (avg_loss.abs * losing_trades.size)
                    else
                      0.0
                    end

    max_win = trades.pluck(:pnl_pct).max || 0.0
    max_loss = trades.pluck(:pnl_pct).min || 0.0

    # Calculate expectancy
    expectancy = total_trades.positive? ? (total_pnl_pct / total_trades) : 0.0

    # Calculate Sharpe-like ratio (simplified)
    returns = trades.pluck(:pnl_pct)
    avg_return = returns.sum / returns.size
    variance = returns.sum { |r| (r - avg_return)**2 } / returns.size
    std_dev = Math.sqrt(variance)
    sharpe_ratio = std_dev.positive? ? (avg_return / std_dev) : 0.0

    {
      total_trades: total_trades,
      winning_trades: winning_trades.size,
      losing_trades: losing_trades.size,
      win_rate: win_rate,
      total_pnl_pct: total_pnl_pct,
      avg_win: avg_win,
      avg_loss: avg_loss,
      profit_factor: profit_factor,
      max_win: max_win,
      max_loss: max_loss,
      expectancy: expectancy,
      sharpe_ratio: sharpe_ratio
    }
  end

  def format_params(params)
    "ST(#{params[:supertrend_period]}/#{params[:supertrend_multiplier]}) " \
      "ADX(#{params[:adx_period]}/#{params[:adx_1m_threshold]}/#{params[:adx_5m_threshold]})"
  end

  def analyze_results
    return puts "\n❌ No valid results to analyze" if @results.empty?

    puts "\n#{'=' * 100}"
    puts 'OPTIMIZATION RESULTS'
    puts "#{'=' * 100}\n"

    # Sort by multiple criteria (composite score)
    @results.each do |r|
      # Composite score: balance between total PnL, win rate, and profit factor
      r[:composite_score] = (
        (r[:total_pnl_pct] * 0.4) +
        (r[:win_rate] * 0.3) +
        (r[:profit_factor] * 10 * 0.2) +
        (r[:sharpe_ratio] * 5 * 0.1)
      )
    end

    sorted_results = @results.sort_by { |r| -r[:composite_score] }

    # Top 10 results
    puts "🏆 TOP 10 PARAMETER COMBINATIONS\n"
    puts '-' * 100
    sorted_results.first(10).each_with_index do |result, idx|
      puts "#{idx + 1}. #{format_params(result)}"
      puts "   PnL: #{result[:total_pnl_pct].round(2)}% | " \
           "WR: #{result[:win_rate].round(1)}% | " \
           "Trades: #{result[:total_trades]} | " \
           "PF: #{result[:profit_factor].round(2)} | " \
           "Exp: #{result[:expectancy].round(2)}%"
      puts ''
    end

    # Best parameters
    best = sorted_results.first
    puts '=' * 100
    puts "🎯 RECOMMENDED PARAMETERS FOR #{@index_key}"
    puts '=' * 100
    puts 'Supertrend:'
    puts "  period: #{best[:supertrend_period]}"
    puts "  base_multiplier: #{best[:supertrend_multiplier]}"
    puts ''
    puts 'ADX:'
    puts "  period: #{best[:adx_period]}"
    puts "  1m threshold: #{best[:adx_1m_threshold]}"
    puts "  5m threshold: #{best[:adx_5m_threshold]}"
    puts ''
    puts 'Performance:'
    puts "  Total PnL: #{best[:total_pnl_pct].round(2)}%"
    puts "  Win Rate: #{best[:win_rate].round(1)}%"
    puts "  Profit Factor: #{best[:profit_factor].round(2)}"
    puts "  Expectancy: #{best[:expectancy].round(2)}% per trade"
    puts "  Sharpe Ratio: #{best[:sharpe_ratio].round(2)}"
    puts "#{'=' * 100}\n"

    # Save to CSV
    save_results_to_csv(sorted_results)
  end

  def save_results_to_csv(results)
    filename = "tmp/optimization_#{@index_key}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv"
    FileUtils.mkdir_p('tmp')

    CSV.open(filename, 'w') do |csv|
      # Header
      csv << [
        'Rank', 'Supertrend Period', 'Supertrend Multiplier',
        'ADX Period', 'ADX 1m Threshold', 'ADX 5m Threshold',
        'Total Trades', 'Win Rate %', 'Total PnL %',
        'Avg Win %', 'Avg Loss %', 'Profit Factor',
        'Max Win %', 'Max Loss %', 'Expectancy %', 'Sharpe Ratio', 'Composite Score'
      ]

      # Data
      results.each_with_index do |result, idx|
        csv << [
          idx + 1,
          result[:supertrend_period],
          result[:supertrend_multiplier],
          result[:adx_period],
          result[:adx_1m_threshold],
          result[:adx_5m_threshold],
          result[:total_trades],
          result[:win_rate].round(2),
          result[:total_pnl_pct].round(2),
          result[:avg_win].round(2),
          result[:avg_loss].round(2),
          result[:profit_factor].round(2),
          result[:max_win].round(2),
          result[:max_loss].round(2),
          result[:expectancy].round(2),
          result[:sharpe_ratio].round(2),
          result[:composite_score].round(2)
        ]
      end
    end

    puts "💾 Results saved to: #{filename}\n"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  index_key = ARGV[0] || 'NIFTY'
  days = ARGV[1] || '30'
  interval = ARGV[2] || '1'

  optimizer = IndicatorParameterOptimizer.new(
    index_key: index_key,
    days_back: days,
    interval: interval
  )

  optimizer.run
end
