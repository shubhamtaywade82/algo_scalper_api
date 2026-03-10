# frozen_string_literal: true

# Advanced Strategy Runner using Dhan API data
class NiftySensexBacktest
  def self.run(symbol:, days: 30, interval: '5')
    puts "\n=== Starting Backtest for #{symbol} (#{days} days, #{interval}m) ==="
    
    # 1. Fetch data from Dhan API
    loader = Backtest::ApiLoader.new(symbol: symbol, days: days, interval: interval)
    data = loader.load
    
    if data.empty?
      puts "❌ No data loaded for #{symbol}. Check API credentials and market status."
      return
    end

    # 2. Initialize Strategy (Example)
    strategy = ExampleNiftyStrategy.new
    
    # 3. Run Engine
    engine = Backtest::Engine.new(data: data, strategy: strategy)
    engine.run
    
    puts "=== Backtest Complete for #{symbol} ===\n"
  end
end

# Example Strategy from before
class ExampleNiftyStrategy
  def initialize
    @in_position = false
  end

  def process(index_price:, option_price:, volume:, oi:)
    # Dynamic thresholds based on index level
    buy_threshold = index_price > 20000 ? 50 : 10 # 50 points move
    
    if !@in_position
      @entry_price = index_price
      @in_position = true
      return :buy
    elsif @in_position && (index_price - @entry_price).abs > buy_threshold
      @in_position = false
      return :exit
    end

    :none
  end
end

# Run Backtests for NIFTY and SENSEX
NiftySensexBacktest.run(symbol: 'NIFTY', days: 30, interval: '5')
NiftySensexBacktest.run(symbol: 'SENSEX', days: 30, interval: '5')
