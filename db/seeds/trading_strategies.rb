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
      def call(context)
        series = context.candles.call("1m")
        return Signals::Hold.new(reason: "no_candle_data") unless series&.candles&.any?

        opening_range_minutes = (params[:opening_range_minutes] || 15).to_i
        candles = series.candles
        session_start = candles.first.timestamp
        range_end = session_start + opening_range_minutes.minutes

        range_candles = candles.select { |c| c.timestamp < range_end }
        return Signals::Hold.new(reason: "opening_range_forming") if candles.last.timestamp < range_end

        range_high = range_candles.map(&:high).max
        range_low = range_candles.map(&:low).min
        latest = candles.last

        if latest.close > range_high
          Signals::BuyCall.new(confidence: 0.7, reason: "orb_breakout_up")
        elsif latest.close < range_low
          Signals::BuyPut.new(confidence: 0.7, reason: "orb_breakout_down")
        else
          Signals::Hold.new(reason: "inside_opening_range")
        end
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
      def call(context)
        series = context.candles.call("5m")
        return Signals::Hold.new(reason: "no_candle_data") unless series&.candles&.any?

        st_period = (params[:supertrend_period] || 10).to_i
        st_multiplier = (params[:supertrend_multiplier] || 3.0).to_f
        adx_threshold = (params[:adx_threshold] || 25).to_i
        adx_period = (params[:adx_period] || 14).to_i

        result = Indicators::Supertrend.new(series: series, period: st_period, base_multiplier: st_multiplier).call
        last_idx = result[:line]&.rindex { |v| !v.nil? }
        return Signals::Hold.new(reason: "supertrend_unavailable") unless last_idx

        adx = series.adx(adx_period)
        return Signals::Hold.new(reason: "adx_unavailable") if adx.nil?
        return Signals::Hold.new(reason: "adx_below_threshold(\#{adx.round(1)})") if adx < adx_threshold

        close = series.candles[last_idx].close
        line_value = result[:line][last_idx]

        if result[:trend] == :bullish && close > line_value
          Signals::BuyCall.new(confidence: 0.7, reason: "supertrend_bullish_adx_confirmed")
        elsif result[:trend] == :bearish && close < line_value
          Signals::BuyPut.new(confidence: 0.7, reason: "supertrend_bearish_adx_confirmed")
        else
          Signals::Hold.new(reason: "trend_not_confirmed")
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
      def call(context)
        series = context.candles.call("3m")
        return Signals::Hold.new(reason: "no_candle_data") unless series&.candles&.any?

        rsi_period = (params[:rsi_period] || 14).to_i
        oversold = (params[:rsi_oversold] || 30).to_i
        overbought = (params[:rsi_overbought] || 70).to_i
        band_pct = (params[:vwap_band_pct] || 0.5).to_f

        vwap = series.current_vwap
        return Signals::Hold.new(reason: "vwap_unavailable") if vwap.nil? || vwap.zero?

        rsi = series.rsi(rsi_period)
        return Signals::Hold.new(reason: "rsi_unavailable") if rsi.nil?

        close = series.candles.last.close
        distance_pct = ((close - vwap) / vwap) * 100

        if distance_pct < -band_pct && rsi < oversold
          Signals::BuyCall.new(confidence: 0.6, reason: "vwap_pullback_rsi_oversold")
        elsif distance_pct > band_pct && rsi > overbought
          Signals::BuyPut.new(confidence: 0.6, reason: "vwap_rejection_rsi_overbought")
        else
          Signals::Hold.new(reason: "no_reversal_setup")
        end
      end
    end
  RUBY
  s.backtest_results = {}
end

# rubocop:enable Layout/LineLength

Rails.logger.info { "Seeded #{TradingStrategy.count} trading strategies" }
