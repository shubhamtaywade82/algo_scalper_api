# frozen_string_literal: true

# Seed default trading strategies for the Strategy Creator feature.

# rubocop:disable Layout/LineLength

# --- 1. ORB Breakout ---
TradingStrategy.find_or_create_by!(name: "ORB Breakout", version: "1.0.0") do |s|
  s.status = "draft"
  s.description = "Opening Range Breakout strategy that enters in the direction of breakout after the opening range is formed."
  s.author = "System"
  s.runtime = "Ruby"
  s.timeframe = "1m"
  s.trade_direction = "both"
  s.instruments = %w[NIFTY BANKNIFTY]
  s.tags = ["Intraday", "Breakout", "Price Action", "ORB"]
  s.parameters = [
    { name: "opening_range_minutes", type: "Integer", default_value: "15", description: "Opening range duration in minutes" },
    { name: "risk_per_trade_pct", type: "Float", default_value: "1.0", description: "Risk per trade as % of capital" },
    { name: "stop_loss_atr", type: "Float", default_value: "1.5", description: "Stop loss multiplier (ATR)" },
    { name: "target_rr", type: "Float", default_value: "2.0", description: "Risk Reward Ratio" },
    { name: "trail_after_rr", type: "Float", default_value: "1.0", description: "Start trailing after RR" }
  ]
  s.checks = { syntax: "passed", logic: "passed", risk: "passed", backtest: "not_run" }
  s.code = <<~RUBY
    class OrbBreakoutStrategy < BaseStrategy
      def initialize(config = {})
        super
        @opening_range = (config[:opening_range_minutes] || 15).to_i
        @risk_per_trade = (config[:risk_per_trade_pct] || 1.0).to_f
      end

      def on_market_open(context)
        @range_high = nil
        @range_low = nil
        @range_start_time = context.market_open_time
      end

      def on_candle_closed(context)
        return if context.position.open?
        return unless context.time > @range_start_time + @opening_range.minutes

        update_opening_range(context)
        return if @range_high.nil? || @range_low.nil?

        breakout = check_breakout(context)
        return unless breakout

        signal = breakout[:direction] == :up ? BuyCallSignal.new : BuyPutSignal.new
        signal.reason = "ORB Breakout \#{breakout[:direction].upcase}"
        signal.metadata = {
          range_high: @range_high,
          range_low: @range_low,
          breakout_price: breakout[:price]
        }
        signal
      end
    end
  RUBY
  s.backtest_results = { net_profit: 124_350, total_trades: 254, win_rate: 62.6, profit_factor: 1.82, max_drawdown: 18_450 }
end

# --- 2. Supertrend ADX ---
TradingStrategy.find_or_create_by!(name: "Supertrend ADX", version: "1.0.0") do |s|
  s.status = "active"
  s.description = "Trend-following strategy using Supertrend indicator confirmed by ADX strength filter."
  s.author = "System"
  s.runtime = "Ruby"
  s.timeframe = "5m"
  s.trade_direction = "both"
  s.instruments = %w[NIFTY BANKNIFTY SENSEX]
  s.tags = %w[Trend Supertrend ADX Momentum]
  s.parameters = [
    { name: "supertrend_period", type: "Integer", default_value: "10", description: "Supertrend ATR period" },
    { name: "supertrend_multiplier", type: "Float", default_value: "3.0", description: "Supertrend ATR multiplier" },
    { name: "adx_threshold", type: "Integer", default_value: "25", description: "Minimum ADX for trend strength" },
    { name: "adx_period", type: "Integer", default_value: "14", description: "ADX calculation period" }
  ]
  s.checks = { syntax: "passed", logic: "passed", risk: "passed", backtest: "passed" }
  s.code = <<~RUBY
    class SupertrendAdxStrategy < BaseStrategy
      def initialize(config = {})
        super
        @st_period = (config[:supertrend_period] || 10).to_i
        @st_multiplier = (config[:supertrend_multiplier] || 3.0).to_f
        @adx_threshold = (config[:adx_threshold] || 25).to_i
      end

      def on_candle_closed(context)
        return if context.position.open?

        st = context.indicator(:supertrend, period: @st_period, multiplier: @st_multiplier)
        adx = context.indicator(:adx, period: @adx_period)

        return unless adx.value >= @adx_threshold

        if st.direction == :bullish && context.close > st.value
          BuyCallSignal.new(reason: 'Supertrend bullish + ADX confirmed')
        elsif st.direction == :bearish && context.close < st.value
          BuyPutSignal.new(reason: 'Supertrend bearish + ADX confirmed')
        end
      end
    end
  RUBY
  s.backtest_results = { net_profit: 89_200, total_trades: 189, win_rate: 58.2, profit_factor: 1.65, max_drawdown: 22_100 }
end

# --- 3. VWAP Reversal ---
TradingStrategy.find_or_create_by!(name: "VWAP Reversal", version: "1.0.0") do |s|
  s.status = "draft"
  s.description = "Mean reversion strategy that trades pullbacks to VWAP with RSI confirmation."
  s.author = "System"
  s.runtime = "Ruby"
  s.timeframe = "3m"
  s.trade_direction = "both"
  s.instruments = %w[NIFTY]
  s.tags = ["Mean Reversion", "VWAP", "RSI"]
  s.parameters = [
    { name: "rsi_period", type: "Integer", default_value: "14", description: "RSI calculation period" },
    { name: "rsi_oversold", type: "Integer", default_value: "30", description: "RSI oversold threshold" },
    { name: "rsi_overbought", type: "Integer", default_value: "70", description: "RSI overbought threshold" },
    { name: "vwap_band_pct", type: "Float", default_value: "0.5", description: "VWAP band width in %" }
  ]
  s.checks = { syntax: "passed", logic: "not_run", risk: "not_run", backtest: "not_run" }
  s.code = <<~RUBY
    class VwapReversalStrategy < BaseStrategy
      def initialize(config = {})
        super
        @rsi_period = (config[:rsi_period] || 14).to_i
        @oversold = (config[:rsi_oversold] || 30).to_i
        @overbought = (config[:rsi_overbought] || 70).to_i
      end

      def on_candle_closed(context)
        return if context.position.open?

        vwap = context.indicator(:vwap)
        rsi = context.indicator(:rsi, period: @rsi_period)

        distance_pct = ((context.close - vwap.value) / vwap.value) * 100

        if distance_pct < -@vwap_band_pct && rsi.value < @oversold
          BuyCallSignal.new(reason: 'VWAP pullback + RSI oversold')
        elsif distance_pct > @vwap_band_pct && rsi.value > @overbought
          BuyPutSignal.new(reason: 'VWAP rejection + RSI overbought')
        end
      end
    end
  RUBY
  s.backtest_results = {}
end

# rubocop:enable Layout/LineLength

Rails.logger.info { "Seeded #{TradingStrategy.count} trading strategies" }
