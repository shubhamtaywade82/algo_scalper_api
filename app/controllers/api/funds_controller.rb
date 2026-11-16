# frozen_string_literal: true

module Api
  class FundsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::PaperFunds

    before_action :authenticate_dashboard_token!

    # GET /api/funds
    def show
      paper_mode = paper_enabled?

      if paper_mode
        render json: paper_snapshot
      else
        render json: live_snapshot
      end
    end

    private

    def live_snapshot
      funds = DhanHQ::Models::Funds.fetch
      # Calculate active MTM from live position trackers if any
      mtm = begin
        Positions::ActivePositionsCache.instance.active_trackers.sum { |t| t.unrealized_pnl.to_f }
      rescue StandardError
        0.0
      end

      cash = funds.available_balance.to_f
      equity = funds.sod_limit.to_f
      margin_used = funds.utilized_amount.to_f
      exposure = (funds.collateral_amount.to_f + funds.receiveable_amount.to_f)
      available = equity - margin_used
      total_collateral = cash + mtm
      day_pnl = compute_day_pnl

      {
        cash: cash,
        equity: equity,
        mtm: mtm,
        exposure: exposure,
        margin_used: margin_used,
        available: available,
        total_collateral: total_collateral,
        day_pnl: day_pnl
      }
    rescue StandardError => e
      Rails.logger.error("[Api::FundsController] Error fetching live funds: #{e.message}")
      { cash: 0.0, equity: 0.0, mtm: 0.0, exposure: 0.0, margin_used: 0.0, available: 0.0, total_collateral: 0.0, day_pnl: 0.0, error: e.message }
    end
  end
end
