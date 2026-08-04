# frozen_string_literal: true

module Api
  class ReplaysController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    MAX_DAYS_BACK = 180
    DEFAULT_DAYS = 30

    def create
      symbol = params[:symbol].to_s.upcase.presence || 'NIFTY'
      days_back = [params[:days_back].to_i.clamp(1, MAX_DAYS_BACK), DEFAULT_DAYS].max

      runner = Backtest::SmcReplayRunner.call(
        symbol: symbol,
        days_back: days_back,
        forward_horizon: 12,
        min_bars: 25,
        include_permission: true,
        permission_mode: 'strict',
        simulate_options: true
      )

      if runner[:error]
        render json: { error: runner[:error] }, status: :unprocessable_content
        return
      end

      render json: {
        symbol: symbol,
        days_back: days_back,
        metrics: build_metrics(runner),
        candles: build_candles(runner),
        trades: build_trades(runner),
        events: build_events(runner),
        spot_rows: runner[:spot_rows]&.map { |r| transform_spot_row(r) } || []
      }
    rescue StandardError => e
      Rails.logger.error("[ReplaysController] Replay failed: #{e.message}")
      render json: { error: 'replay_failed', message: e.message }, status: :internal_server_error
    end

    private

    def build_metrics(runner)
      opt = runner[:options_summary] || {}
      spot = runner[:spot_summary] || {}

      {
        netPnl: (opt[:total_pnl_percent] || 0) * 1000,
        netPnlPct: opt[:total_pnl_percent] || 0,
        totalTrades: opt[:total_trades] || 0,
        winRate: opt[:win_rate] || 0,
        winningTrades: opt[:winning_trades] || 0,
        losingTrades: opt[:losing_trades] || 0,
        profitFactor: compute_profit_factor(opt[:trades] || []),
        maxDrawdown: 0,
        maxDrawdownPct: 0,
        avgTrade: opt[:expectancy] || 0,
        expectancy: opt[:expectancy] || 0,
        signalCount: spot[:count] || 0,
        signalWinRate: spot[:directional_win_rate] || 0
      }
    end

    def build_candles(runner)
      series = runner.instance_variable_get(:@series_5m)
      return [] unless series&.candles

      series.candles.map do |c|
        {
          time: c.timestamp.to_i,
          open: c.open.to_f,
          high: c.high.to_f,
          low: c.low.to_f,
          close: c.close.to_f,
          volume: c.volume.to_i
        }
      end
    end

    def build_trades(runner)
      (runner[:option_trades] || []).each_with_index.map do |t, i|
        pnl_rupees = (t[:pnl_percent].to_f / 100.0) * 250_000
        {
          id: i + 1,
          time: t[:entry_time]&.strftime('%d %b %H:%M:%S'),
          entry_timestamp: t[:entry_time]&.to_i,
          exit_timestamp: t[:exit_time]&.to_i,
          type: t[:signal_type].to_s == 'ce' ? 'BUY' : 'SELL',
          inst: "#{runner[:symbol]} #{t[:signal_type].to_s.upcase}",
          qty: 75,
          entry: t[:entry_price].to_f.round(2),
          exit: t[:exit_price].to_f.round(2),
          pnl: pnl_rupees.round(2),
          pnlPct: t[:pnl_percent].round(2),
          status: t[:pnl_percent].to_f.positive? ? 'WIN' : 'LOSS'
        }
      end
    end

    def build_events(runner)
      events = []
      market_open_ts = runner[:spot_rows]&.first&.dig(:timestamp)&.to_i || Time.zone.now.to_i
      events << { time: '09:00:00', text: 'Market Open', type: 'system', timestamp: market_open_ts }

      (runner[:spot_rows] || []).each do |row|
        t = row[:timestamp]&.strftime('%H:%M:%S') || '--'
        events << { time: t, text: "#{row[:action]} signal (#{row[:reason]})", type: 'signal', timestamp: row[:timestamp]&.to_i }
      end

      (runner[:option_trades] || []).each do |t|
        entry_t = t[:entry_time]&.strftime('%H:%M:%S') || '--'
        exit_t = t[:exit_time]&.strftime('%H:%M:%S') || '--'
        events << { time: entry_t, text: "Order placed #{t[:signal_type].to_s.upcase}", type: 'order', timestamp: t[:entry_time]&.to_i }
        events << { time: entry_t, text: "Order filled @ #{t[:entry_price].to_f.round(2)}", type: 'order', timestamp: t[:entry_time]&.to_i }
        events << { time: exit_t, text: "Exit (#{t[:exit_reason]}) @ #{t[:exit_price].to_f.round(2)}", type: 'order', timestamp: t[:exit_time]&.to_i }
      end

      events.sort_by { |e| e[:timestamp] || 0 }
    end

    def transform_spot_row(row)
      {
        barIndex: row[:bar_index],
        timestamp: row[:timestamp],
        action: row[:action],
        reason: row[:reason],
        rr: row[:rr],
        permission: row[:permission],
        forwardHorizonBars: row[:forward_horizon_bars],
        mfeUpPct: row[:mfe_up_pct],
        mfeDownPct: row[:mfe_down_pct],
        horizonReturnPct: row[:horizon_return_pct],
        directionalWin: row[:directional_win]
      }
    end

    def compute_profit_factor(trades)
      wins = trades.select { |t| t[:pnl_percent].to_f.positive? }
      losses = trades.select { |t| t[:pnl_percent].to_f <= 0 }
      gross_win = wins.sum { |t| t[:pnl_percent].to_f }
      gross_loss = losses.sum { |t| t[:pnl_percent].to_f }.abs
      return 0.0 if gross_loss.zero? && gross_win.zero?
      return 5.0 if gross_loss.zero?

      (gross_win / gross_loss).round(2)
    end
  end
end
