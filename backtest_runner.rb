# frozen_string_literal: true

# Institutional Strategy Adapter for Backtesting
class InstitutionalOptionsStrategy
  def initialize(symbol:)
    @symbol = symbol
    @series = CandleSeries.new(symbol: symbol, interval: '5')
    @filter = Entries::EntryFilterEngine.new(series: @series, symbol: symbol)
    @in_position = false
  end

  def process(tick)
    # 1. Update the series with REAL OHLC data from Dhan API
    candle = Candle.new(
      timestamp: tick[:timestamp],
      open: tick[:open],
      high: tick[:high],
      low: tick[:low],
      close: tick[:index_price],
      volume: tick[:volume]
    )
    @series.add_candle(candle)

    # 2. Need minimum history for ATR and Range averages
    return :none if @series.candles.size < 21

    # 3. Apply Institutional Entry Filter (Market Structure + Expansion + Volatility)
    if !@in_position
      # Check for Bullish entry (Institutional alignment)
      if @filter.valid_entry?(direction: :bullish)
        @in_position = true
        @entry_price = tick[:index_price]
        return :buy
      end
    else
      # 4. Institutional Exit (MFE-style underlying logic)
      profit_pct = (tick[:index_price] - @entry_price) / @entry_price

      # Stop Loss: -0.3% index move | Take Profit: +0.8% index move
      if profit_pct < -0.003 || profit_pct > 0.008
        @in_position = false
        return :exit
      end
    end

    :none
  end
end

class NiftySensexBacktest
  def self.run(symbol:, days: 30, interval: '5')
    puts "\n=== INSTITUTIONAL BACKTEST: #{symbol} ==="

    loader = Backtest::ApiLoader.new(symbol: symbol, days: days, interval: interval)
    data = loader.load

    if data.empty?
      puts "❌ No data loaded."
      return
    end

    strategy = InstitutionalOptionsStrategy.new(symbol: symbol)
    engine = Backtest::Engine.new(data: data, strategy: strategy)
    engine.run
  end
end

# Run the Fixed Backtests
NiftySensexBacktest.run(symbol: 'NIFTY', days: 30, interval: '5')
NiftySensexBacktest.run(symbol: 'SENSEX', days: 30, interval: '5')
