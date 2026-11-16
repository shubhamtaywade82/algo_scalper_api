# frozen_string_literal: true

module Api
  # GET /api/reports/performance
  class PerformanceReportsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::ReportDateRange

    before_action :authenticate_dashboard_token!

    def show
      scope = date_filtered_scope(PositionTracker.exited)

      total = scope.count
      wins = scope.where("last_pnl_rupees > 0").count
      losses = scope.where("last_pnl_rupees <= 0").count
      win_rate = total.positive? ? (wins.to_f / total * 100).round(2) : 0.0

      net_pnl = scope.sum(:last_pnl_rupees).to_f
      avg_win = wins.positive? ? (scope.where("last_pnl_rupees > 0").sum(:last_pnl_rupees).to_f / wins).round(2) : 0.0
      avg_loss = losses.positive? ? (scope.where("last_pnl_rupees <= 0").sum(:last_pnl_rupees).to_f / losses).round(2) : 0.0

      max_win = scope.maximum(:last_pnl_rupees).to_f
      max_loss = scope.minimum(:last_pnl_rupees).to_f

      # Profit factor is gross profit / gross loss; avg_win / avg_loss is the payoff
      # ratio and overstated PF (2.33 vs a true ~1.01 on the paper history).
      gross_loss = scope.where("last_pnl_rupees < 0").sum(:last_pnl_rupees).to_f.abs
      gross_profit = scope.where("last_pnl_rupees > 0").sum(:last_pnl_rupees).to_f
      profit_factor = gross_loss.positive? ? (gross_profit / gross_loss).round(2) : 0.0

      daily = scope.group(Arel.sql("DATE(exited_at)"))
                   .pluck(Arel.sql("DATE(exited_at)"), Arel.sql("SUM(last_pnl_rupees)"))
                   .map { |date, pnl| { date: date.to_s, pnl: pnl.to_f.round(2) } }
                   .sort_by { |d| d[:date] }

      render json: {
        success: true,
        summary: {
          total_trades: total,
          wins: wins,
          losses: losses,
          win_rate_percent: win_rate,
          net_pnl: net_pnl,
          avg_win: avg_win,
          avg_loss: avg_loss,
          max_win: max_win,
          max_loss: max_loss,
          profit_factor: profit_factor,
          expectancy: total.positive? ? (net_pnl / total).round(2) : 0.0
        },
        daily: daily
      }
    end
  end
end
