# frozen_string_literal: true

module Api
  class EquityCurveController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      date_from = parse_date(params[:date_from], 90.days.ago.to_date)
      date_to = parse_date(params[:date_to], Time.zone.today)

      # Explicit mode filter: this table now also holds live-mode KPI rows
      # (Ledger::DailyCloseJob), which don't share a comparable closing_cash concept.
      records = PaperDailyWallet
                .where(trading_date: date_from..date_to, mode: 'paper')
                .order(trading_date: :asc)

      if records.any?
        render json: build_from_wallet(records)
      else
        render json: build_from_positions(date_from, date_to)
      end
    end

    private

    def build_from_wallet(records)
      peak = 0.0
      records.map do |r|
        equity = r.closing_cash.to_f
        peak = equity if equity > peak
        drawdown_pct = peak.positive? ? ((equity - peak) / peak) * 100 : 0.0

        {
          time: r.trading_date.to_time.to_i,
          equity: equity,
          drawdown_pct: drawdown_pct.round(4),
          peak: peak
        }
      end
    end

    def build_from_positions(date_from, date_to)
      daily_pnl = PositionTracker.exited
                                 .where(exited_at: date_from.beginning_of_day..date_to.end_of_day)
                                 .group("DATE(exited_at)")
                                 .sum(:last_pnl_rupees)

      return [] if daily_pnl.empty?

      initial_capital = 250_000.0
      equity = initial_capital
      peak = equity
      points = []

      daily_pnl.sort_by { |date, _| date }.each do |date, pnl|
        equity += pnl.to_f
        peak = equity if equity > peak
        drawdown_pct = peak.positive? ? ((equity - peak) / peak) * 100 : 0.0

        points << {
          time: date.to_time.to_i,
          equity: equity.round(2),
          drawdown_pct: drawdown_pct.round(4),
          peak: peak.round(2)
        }
      end

      points
    end

    def parse_date(raw, default)
      return default if raw.blank?

      Date.parse(raw.to_s)
    rescue ArgumentError, TypeError
      default
    end
  end
end
