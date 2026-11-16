# frozen_string_literal: true

module Api
  # GET /api/reports/pnl
  class PnlReportsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::ReportDateRange

    before_action :authenticate_dashboard_token!

    def show
      scope = date_filtered_scope(PositionTracker.exited)
      total_trades = scope.count
      winning_trades = scope.where("last_pnl_rupees > 0").count
      losing_trades = scope.where("last_pnl_rupees <= 0").count

      net_pnl = scope.sum(:last_pnl_rupees).to_f
      win_rate = total_trades.positive? ? (winning_trades.to_f / total_trades * 100).round(2) : 0.0

      gross_profit = scope.where("last_pnl_rupees > 0").sum(:last_pnl_rupees).to_f
      gross_loss = scope.where("last_pnl_rupees <= 0").sum(:last_pnl_rupees).to_f

      render json: {
        success: true,
        summary: {
          total_trades: total_trades,
          winning_trades: winning_trades,
          losing_trades: losing_trades,
          win_rate_percent: win_rate,
          net_pnl: net_pnl,
          gross_profit: gross_profit,
          gross_loss: gross_loss,
          total_brokerage: scope.sum(:charges_rupees).to_f
        }
      }
    end
  end
end
