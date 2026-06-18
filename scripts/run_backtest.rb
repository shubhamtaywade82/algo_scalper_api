# frozen_string_literal: true

require_relative "../config/environment"

# Wrapper to run backtest and output JSON metrics
def run_backtest
  # Use NIFTY as default symbol for optimization
  symbol = ENV["BACKTEST_SYMBOL"] || "NIFTY"
  days = (ENV["BACKTEST_DAYS"] || 30).to_i

  # In a real scenario, we'd load strategy_config.yml and inject it into the strategy
  # For now, let's assume the strategy reads from the config file

  service = BacktestService.run(
    symbol: symbol,
    days_back: days,
    strategy: SimpleMomentumStrategy
  )
  summary = service.summary

  if summary.empty?
    # Return zeroed metrics if no trades
    puts({
      profit_factor: 0.0,
      drawdown: 0.0,
      win_rate: 0.0,
      total_trades: 0
    }.to_json)
    return
  end

  # Calculate a simple profit factor (gross win / gross loss)
  wins = summary[:trades].select { |t| t[:pnl_percent].positive? }.sum { |t| t[:pnl_percent] }
  losses = summary[:trades].select { |t| t[:pnl_percent].negative? }.sum { |t| t[:pnl_percent] }.abs

  profit_factor = if losses.zero?
wins.positive? ? 5.0 : 0.0
                  else
(wins / losses).round(2)
                  end

  # Estimate drawdown (simplified as max loss in a single trade for this demo)
  drawdown = summary[:max_loss].abs / 100.0

  metrics = {
    profit_factor: profit_factor,
    drawdown: drawdown,
    win_rate: summary[:win_rate] / 100.0,
    total_trades: summary[:total_trades]
  }

  puts metrics.to_json
rescue StandardError => e
  warn "Backtest failed: #{e.message}"
  exit 1
end

run_backtest
