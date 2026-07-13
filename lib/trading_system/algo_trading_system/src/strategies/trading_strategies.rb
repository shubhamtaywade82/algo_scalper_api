# frozen_string_literal: true

require 'enumerable/statistics'
require 'ostruct'
require_relative '../utils/greeks_wrapper'

# Trading Strategies for Intraday Options
module TradingStrategies
  # Base strategy class - Signals on SPOT, Executes on PREMIUM
  class BaseStrategy
    def initialize(options = {})
      @lookback_period = options[:lookback_period] || 20
      @history = []
    end

    def add_bar(bar)
      @history << bar
      @history = @history.last(@lookback_period + 100) if @history.length > @lookback_period + 100
    end

    def signal
      raise NotImplementedError, 'Subclass must implement signal method'
    end

    protected

    # Indicators calculated on the UNDERLYING SPOT price
    def spot_prices
      @history.map { |b| b[:spot] || b[:close] }
    end

    def rsi(period = 14)
      return nil if spot_prices.length < period + 1
      calculate_rsi_on(spot_prices, period)
    end

    def macd(fast: 12, slow: 26, signal_period: 9)
      return nil if spot_prices.length < slow + signal_period
      calculate_macd_on(spot_prices, fast, slow, signal_period)
    end

    def ema(period)
      return nil if spot_prices.length < period
      calculate_ema(spot_prices, period).last
    end

    def bollinger_bands(period = 20, dev = 2)
      return nil if spot_prices.length < period
      prices = spot_prices.last(period)
      sma = prices.sum / period.to_f
      variance = prices.map { |p| (p - sma)**2 }.sum / period.to_f
      std_dev = Math.sqrt(variance)
      {
        middle: sma,
        upper: sma + (dev * std_dev),
        lower: sma - (dev * std_dev)
      }
    end

    private

    def calculate_rsi_on(series, period)
      changes = series.each_cons(2).map { |a, b| b - a }
      gains = changes.map { |c| c.positive? ? c : 0 }
      losses = changes.map { |c| c.negative? ? -c : 0 }
      avg_gain = gains.last(period).sum / period.to_f
      avg_loss = losses.last(period).sum / period.to_f
      return 50 if avg_loss == 0
      rs = avg_gain / avg_loss
      100 - (100 / (1 + rs))
    end

    def calculate_macd_on(series, fast, slow, signal_period)
      ema_fast = calculate_ema(series, fast)
      ema_slow = calculate_ema(series, slow)
      min_len = [ema_fast.length, ema_slow.length].min
      macd_line_history = ema_fast.last(min_len).zip(ema_slow.last(min_len)).map { |f, s| f - s }
      return nil if macd_line_history.length < signal_period
      macd_line = macd_line_history.last
      signal_line = calculate_ema(macd_line_history, signal_period).last
      { histogram: macd_line - signal_line }
    end

    def calculate_ema(values, period)
      multiplier = 2.0 / (period + 1)
      ema = values.first(period).sum / period.to_f
      result = [ema]
      values.drop(period).each { |v| result << (v * multiplier) + (result.last * (1 - multiplier)) }
      result
    end
  end

  # RSI + MACD Reversal (Signals on Spot)
  class RSIMACDReversal < BaseStrategy
    def signal
      current_rsi = rsi(14)
      macd_data = macd
      return { action: 'HOLD' } if current_rsi.nil? || macd_data.nil?

      if current_rsi < 35 && macd_data[:histogram].positive?
        { action: 'BUY', direction: 'LONG', reason: "Spot RSI Oversold (#{current_rsi.round(1)}) + MACD Bullish" }
      elsif current_rsi > 65 && macd_data[:histogram].negative?
        { action: 'SELL', direction: 'SHORT', reason: "Spot RSI Overbought (#{current_rsi.round(1)}) + MACD Bearish" }
      else
        { action: 'HOLD' }
      end
    end
  end

  # EMA Crossover (Signals on Spot)
  class EmaCrossover < BaseStrategy
    def signal
      fast = ema(9)
      slow = ema(21)
      return { action: 'HOLD' } if fast.nil? || slow.nil?

      if fast > slow
        { action: 'BUY', direction: 'LONG', reason: "Spot EMA 9/21 Bullish Crossover" }
      elsif fast < slow
        { action: 'SELL', direction: 'SHORT', reason: "Spot EMA 9/21 Bearish Crossover" }
      else
        { action: 'HOLD' }
      end
    end
  end

  # Bollinger Breakout (Signals on Spot)
  class BollingerBreakout < BaseStrategy
    def signal
      bands = bollinger_bands(20, 2)
      last_price = spot_prices.last
      return { action: 'HOLD' } if bands.nil? || last_price.nil?

      if last_price > bands[:upper]
        { action: 'BUY', direction: 'LONG', reason: "Spot Price Breakout Upper BB" }
      elsif last_price < bands[:lower]
        { action: 'SELL', direction: 'SHORT', reason: "Spot Price Breakdown Lower BB" }
      else
        { action: 'HOLD' }
      end
    end
  end

  # Supertrend (Approximate for Spot)
  class Supertrend < BaseStrategy
    def initialize(options = {})
      super(lookback_period: options[:period] || 10)
      @multiplier = options[:multiplier] || 3
      @prev_trend = nil
    end

    def signal
      return { action: 'HOLD' } if @history.length < @lookback_period
      
      # Simplified trend following
      src = spot_prices.last
      short_ema = ema(10)
      long_ema = ema(30)
      
      return { action: 'HOLD' } if short_ema.nil? || long_ema.nil?

      if short_ema > long_ema
        { action: 'BUY', direction: 'LONG', reason: "Supertrend-like Bullish EMA" }
      elsif short_ema < long_ema
        { action: 'SELL', direction: 'SHORT', reason: "Supertrend-like Bearish EMA" }
      else
        { action: 'HOLD' }
      end
    end
  end

  class StrategyFactory
    STRATEGIES = {
      rsi_macd: RSIMACDReversal,
      ema_crossover: EmaCrossover,
      bollinger_breakout: BollingerBreakout,
      supertrend: Supertrend,
      scalper_strategy: nil # Loaded dynamically or via require
    }.freeze

    def self.create(type, config = {})
      strategy_class = STRATEGIES[type.to_sym]
      
      # Special case for scalper_strategy if it's in a separate file
      if type.to_sym == :scalper_strategy
        require_relative 'scalper_strategy'
        strategy_class = ScalperStrategy
      end

      (strategy_class || RSIMACDReversal).new(config)
    end

    def self.available_strategies
      STRATEGIES.keys
    end
  end
end
