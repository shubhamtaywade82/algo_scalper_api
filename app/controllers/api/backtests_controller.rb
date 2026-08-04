# frozen_string_literal: true

module Api
  class BacktestsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    MAX_DAYS_BACK = 365
    DEFAULT_DAYS = 30
    INITIAL_CAPITAL = 250_000.0

    def create
      symbol = params[:symbol].to_s.upcase.presence || 'NIFTY'
      days_back = [params[:days_back].to_i.clamp(1, MAX_DAYS_BACK), DEFAULT_DAYS].max
      interval = params[:interval].presence || '5'

      backtest = BacktestService.run(
        symbol: symbol,
        interval: interval,
        days_back: days_back,
        strategy: SupertrendBacktestStrategy
      )

      summary = backtest.summary

      if summary.empty?
        render json: {
          metrics: zeroed_metrics,
          trades: [],
          equity_curve: [],
          config: config_summary(symbol, interval, days_back)
        }
        return
      end

      render json: {
        metrics: build_metrics(summary),
        trades: build_trades(summary[:trades]),
        equity_curve: build_equity_curve(summary[:trades]),
        config: config_summary(symbol, interval, days_back)
      }
    rescue StandardError => e
      Rails.logger.error("[BacktestsController] Backtest failed: #{e.message}")
      render json: { error: 'backtest_failed', message: e.message }, status: :internal_server_error
    end

    private

    def build_metrics(summary)
      trades = summary[:trades]
      total_pnl_rupees = trades.sum { |t| (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL }
      wins = trades.select { |t| t[:pnl_percent].positive? }
      losses = trades.select { |t| t[:pnl_percent] <= 0 }
      gross_win = wins.sum { |t| (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL }
      gross_loss = losses.sum { |t| (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL }.abs

      equity = 0.0
      peak = 0.0
      max_dd = 0.0
      curve = []
      trades.sort_by { |t| t[:exit_time] }.each do |t|
        pnl_rupees = (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL
        equity += pnl_rupees
        peak = equity if equity > peak
        dd = peak - equity
        max_dd = dd if dd > max_dd
        curve << equity
      end

      {
        netProfit: total_pnl_rupees.round(2),
        netProfitPct: summary[:total_pnl_percent],
        totalReturn: summary[:total_pnl_percent],
        winRate: summary[:win_rate],
        totalTrades: summary[:total_trades],
        winningTrades: summary[:winning_trades],
        losingTrades: summary[:losing_trades],
        profitFactor: if gross_loss.zero?
gross_win.positive? ? 5.0 : 0.0
                      else
(gross_win / gross_loss).round(2)
                      end,
        maxDrawdown: max_dd.round(2),
        maxDrawdownPct: peak.positive? ? ((max_dd / (INITIAL_CAPITAL + peak)) * 100).round(2) : 0,
        expectancy: summary[:expectancy],
        avgWinPct: summary[:avg_win_percent],
        avgLossPct: summary[:avg_loss_percent]
      }
    end

    def build_trades(trades)
      trades.each_with_index.map do |t, i|
        pnl_rupees = ((t[:pnl_percent] / 100.0) * INITIAL_CAPITAL).round(2)
        {
          id: i + 1,
          datetime: t[:exit_time]&.strftime('%d %b %H:%M'),
          instrument: "#{@backtest_symbol || 'NIFTY'} #{t[:signal_type].to_s.upcase}",
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

    def build_equity_curve(trades)
      equity = 0.0
      peak = 0.0
      sorted = trades.sort_by { |t| t[:exit_time] || Time.zone.now }

      sorted.filter_map do |t|
        next unless t[:exit_time]

        pnl_rupees = (t[:pnl_percent] / 100.0) * INITIAL_CAPITAL
        equity += pnl_rupees
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

    def config_summary(symbol, interval, days_back)
      {
        symbol: symbol,
        interval: "#{interval}m",
        days_back: days_back,
        initial_capital: INITIAL_CAPITAL,
        strategy: 'SupertrendBacktestStrategy'
      }
    end

    def zeroed_metrics
      {
        netProfit: 0, netProfitPct: 0, totalReturn: 0,
        winRate: 0, totalTrades: 0, winningTrades: 0, losingTrades: 0,
        profitFactor: 0, maxDrawdown: 0, maxDrawdownPct: 0,
        expectancy: 0, avgWinPct: 0, avgLossPct: 0
      }
    end
  end
end
