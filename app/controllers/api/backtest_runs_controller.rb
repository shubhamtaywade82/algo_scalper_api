# frozen_string_literal: true

require 'csv'

module Api
  # Async backtest engine (Backtest::OptionsBuyingBacktester via BacktestRunJob) — separate
  # resource from Api::BacktestsController, which stays untouched: the dashboard's
  # useBacktest.js store calls POST /api/backtests synchronously today and depends on that
  # exact response shape, so that endpoint is not a safe place to introduce async job polling.
  class BacktestRunsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    MAX_DAYS_BACK = 365
    MAX_PER_PAGE = 100
    # Matches Backtest::OptionsBuyingBacktester::DEFAULT_PARAMS — the engine does raw
    # arithmetic against these (e.g. `entry_price * stop_loss_pct`), so they must be cast
    # to Float here rather than passed through as whatever the client sent (a form-encoded
    # request would otherwise hand the job strings, crashing deep inside BacktestRunJob).
    NUMERIC_PARAM_KEYS = %w[stop_loss_pct target_pct giveback_activation_pct giveback_pct max_hold_minutes].freeze

    def create
      strategy_version = resolve_strategy_version(params[:strategy_slug])
      if params[:strategy_slug].present? && strategy_version.nil?
        return render json: { error: 'strategy_not_found', slug: params[:strategy_slug] }, status: :unprocessable_entity
      end

      run = BacktestRun.create!(
        symbol: params[:symbol].to_s.upcase.presence || 'NIFTY',
        days_back: params[:days_back].presence&.to_i&.clamp(1, MAX_DAYS_BACK) || 90,
        trading_type: params[:trading_type].presence || 'options',
        entry_interval: params[:entry_interval].presence || '5',
        params: strategy_params,
        strategy_version: strategy_version
      )
      BacktestRunJob.perform_later(run.id)

      render json: { backtest_run_id: run.id, status: run.status }, status: :accepted
    end

    def index
      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 1].max, MAX_PER_PAGE].min

      scope = BacktestRun.recent_first
      total = scope.count
      runs = scope.offset((page - 1) * per_page).limit(per_page)

      render json: {
        runs: runs.map { |r| run_summary(r) },
        meta: { total: total, page: page, per_page: per_page, pages: [1, (total.to_f / per_page).ceil].max }
      }
    end

    def show
      run = BacktestRun.find(params[:id])
      render json: run_detail(run)
    end

    def download_csv
      run = BacktestRun.find(params[:id])
      unless run.completed?
        render json: { error: 'not_completed', status: run.status }, status: :unprocessable_entity
        return
      end

      trades = run.results['trades'] || []
      csv_string = CSV.generate do |csv|
        csv << %w[EntryTime ExitTime EntryPrice ExitPrice PnL PnLPct ExitReason MinutesHeld]
        trades.each do |t|
          csv << [t['entry_time'], t['exit_time'], t['entry_price'], t['exit_price'],
                  t['pnl'], t['pnl_pct'], t['exit_reason'], t['minutes_held']]
        end
      end
      send_data csv_string, filename: "backtest_#{run.id}_#{run.symbol}_#{Time.zone.today}.csv", type: 'text/csv'
    end

    private

    def resolve_strategy_version(slug)
      return nil if slug.blank?

      version = ::Strategies::Record.find_by(slug: slug)&.current_version
      return version if version

      ::Strategies::Discovery.sync! # cold-start: no daemon has reconciled this box yet
      ::Strategies::Record.find_by(slug: slug)&.current_version
    end

    def strategy_params
      raw = params[:params].presence&.to_unsafe_h || {}
      raw.slice(*NUMERIC_PARAM_KEYS).each_with_object({}) do |(key, value), casted|
        casted[key] = Float(value)
      rescue ArgumentError, TypeError
        next
      end
    end

    def run_summary(run)
      {
        id: run.id, symbol: run.symbol, days_back: run.days_back, status: run.status,
        total_trades: run.total_trades, win_rate: run.win_rate, total_pnl: run.total_pnl,
        max_drawdown: run.max_drawdown, created_at: run.created_at,
        strategy_slug: run.strategy_version&.strategy_record&.slug
      }
    end

    def run_detail(run)
      run_summary(run).merge(
        trading_type: run.trading_type, entry_interval: run.entry_interval, params: run.params,
        error_message: run.error_message, started_at: run.started_at, finished_at: run.finished_at,
        results: run.results
      )
    end
  end
end
