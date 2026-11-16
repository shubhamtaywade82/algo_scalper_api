# frozen_string_literal: true

module Api
  # GET /api/reports/pnl_by_strategy
  class StrategyPnlReportsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::ReportDateRange

    before_action :authenticate_dashboard_token!

    def index
      scope = date_filtered_scope(PositionTracker.exited)

      rows = scope.group(:entry_strategy)
                  .pluck(
                    Arel.sql("entry_strategy"),
                    Arel.sql("COUNT(*)"),
                    Arel.sql("SUM(CASE WHEN last_pnl_rupees > 0 THEN 1 ELSE 0 END)"),
                    Arel.sql("SUM(CASE WHEN last_pnl_rupees <= 0 THEN 1 ELSE 0 END)"),
                    Arel.sql("SUM(last_pnl_rupees)"),
                    Arel.sql("AVG(last_pnl_rupees)")
                  )

      breakdown = rows.map do |name, total, wins, losses, net_pnl, avg_pnl|
        {
          strategy: name.presence || "unattributed",
          total_trades: total,
          wins: wins,
          losses: losses,
          net_pnl: net_pnl.to_f.round(2),
          avg_pnl: avg_pnl.to_f.round(2),
          win_rate_percent: total.positive? ? (wins.to_f / total * 100).round(2) : 0.0
        }
      end

      render json: { success: true, breakdown: breakdown.sort_by { |r| -r[:net_pnl] } }
    end
  end
end
