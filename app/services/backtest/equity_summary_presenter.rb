# frozen_string_literal: true

module Backtest
  # Shapes a Backtest::StrategyBacktester summary into the metrics/trades/equity_curve/config
  # JSON the dashboard's Backtester.jsx view renders. Extracted from Api::BacktestsController
  # so the same shaping runs both inline (nothing to shape, see zeroed) and inside
  # EquityBacktestJob (which runs off the request thread).
  class EquitySummaryPresenter
    INITIAL_CAPITAL = 250_000.0

    def self.call(summary, symbol:, interval:, days_back:)
      new(summary, symbol: symbol, interval: interval, days_back: days_back).call
    end

    def initialize(summary, symbol:, interval:, days_back:)
      @summary = summary
      @symbol = symbol
      @interval = interval
      @days_back = days_back
    end

    def call
      return zeroed_result if @summary.blank? || @summary[:trades].blank?

      {
        metrics: build_metrics,
        trades: build_trades,
        equity_curve: build_equity_curve,
        config: config_summary
      }
    end

    private

    def build_metrics
      trades = @summary[:trades]
      total_pnl_rupees = trades.sum { |t| (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL }
      wins = trades.select { |t| t[:pnl_percent].positive? }
      losses = trades.select { |t| t[:pnl_percent] <= 0 }
      gross_win = wins.sum { |t| (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL }
      gross_loss = losses.sum { |t| (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL }.abs
      max_dd, peak = drawdown(trades)

      {
        netProfit: total_pnl_rupees.round(2),
        netProfitPct: @summary[:total_pnl_percent],
        totalReturn: @summary[:total_pnl_percent],
        winRate: @summary[:win_rate],
        totalTrades: @summary[:total_trades],
        winningTrades: @summary[:winning_trades],
        losingTrades: @summary[:losing_trades],
        profitFactor: profit_factor(gross_win, gross_loss),
        maxDrawdown: max_dd.round(2),
        maxDrawdownPct: peak.positive? ? ((max_dd / (INITIAL_CAPITAL + peak)) * 100).round(2) : 0,
        expectancy: @summary[:expectancy],
        avgWinPct: @summary[:avg_win_percent],
        avgLossPct: @summary[:avg_loss_percent]
      }
    end

    def profit_factor(gross_win, gross_loss)
      return gross_win.positive? ? 5.0 : 0.0 if gross_loss.zero?

      (gross_win / gross_loss).round(2)
    end

    def drawdown(trades)
      equity = 0.0
      peak = 0.0
      max_dd = 0.0
      trades.sort_by { |t| t[:exit_time] }.each do |t|
        equity += (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL
        peak = equity if equity > peak
        dd = peak - equity
        max_dd = dd if dd > max_dd
      end
      [max_dd, peak]
    end

    def build_trades
      @summary[:trades].each_with_index.map do |t, i|
        pnl_rupees = ((t[:pnl_percent] / 100.0) * INITIAL_CAPITAL).round(2)
        {
          id: i + 1,
          datetime: t[:exit_time]&.strftime('%d %b %H:%M'),
          instrument: "#{@symbol} #{t[:signal_type].to_s.upcase}",
          type: t[:pnl_percent].positive? ? 'BUY' : 'SELL',
          entry: t[:entry_price].to_f.round(2),
          exit: t[:exit_price].to_f.round(2),
          pnl: pnl_rupees,
          pnl_pct: t[:pnl_percent].round(2),
          status: t[:pnl_percent].positive? ? 'WIN' : 'LOSS',
          exit_reason: t[:exit_reason],
          bars_held: t[:bars_held]
        }
      end
    end

    def build_equity_curve
      equity = 0.0
      peak = 0.0
      sorted = @summary[:trades].sort_by { |t| t[:exit_time] || Time.zone.now }

      sorted.filter_map do |t|
        next unless t[:exit_time]

        equity += (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL
        peak = equity if equity > peak
        drawdown_pct = peak.positive? ? ((equity - peak) / peak) * 100 : 0.0

        {
          time: t[:exit_time].to_i,
          equity: (INITIAL_CAPITAL + equity).round(2),
          drawdown_pct: drawdown_pct.round(4),
          peak: (INITIAL_CAPITAL + peak).round(2)
        }
      end
    end

    def config_summary
      {
        symbol: @symbol,
        interval: "#{@interval}m",
        days_back: @days_back,
        initial_capital: INITIAL_CAPITAL,
        strategy: 'SupertrendBacktestStrategy'
      }
    end

    def zeroed_result
      {
        metrics: {
          netProfit: 0, netProfitPct: 0, totalReturn: 0,
          winRate: 0, totalTrades: 0, winningTrades: 0, losingTrades: 0,
          profitFactor: 0, maxDrawdown: 0, maxDrawdownPct: 0,
          expectancy: 0, avgWinPct: 0, avgLossPct: 0
        },
        trades: [],
        equity_curve: [],
        config: config_summary
      }
    end
  end
end
