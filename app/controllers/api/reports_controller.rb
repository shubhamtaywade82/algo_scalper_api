# frozen_string_literal: true

module Api
  class ReportsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      render json: {
        success: true,
        message: "Reports index endpoints available"
      }
    end

    def pnl
      closed_trackers = PositionTracker.where(status: 'closed')
      total_trades = closed_trackers.count
      winning_trades = closed_trackers.where("last_pnl_rupees > 0").count
      losing_trades = closed_trackers.where("last_pnl_rupees <= 0").count

      net_pnl = closed_trackers.sum(:last_pnl_rupees).to_f
      win_rate = total_trades.positive? ? (winning_trades.to_f / total_trades * 100).round(2) : 0.0

      gross_profit = closed_trackers.where("last_pnl_rupees > 0").sum(:last_pnl_rupees).to_f
      gross_loss = closed_trackers.where("last_pnl_rupees <= 0").sum(:last_pnl_rupees).to_f

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
          total_brokerage: total_trades * 40.0 # Estimate 40 INR round trip brokerage per trade
        }
      }
    end
  end
end
