# frozen_string_literal: true

module Api
  class OrdersController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      scope = PositionTracker.includes(:instrument)
                             .order(created_at: :desc)
                             .limit(10)

      orders = scope.map do |tracker|
        {
          id: tracker.id,
          order_no: tracker.order_no,
          symbol: tracker.symbol,
          side: tracker.side,
          quantity: tracker.quantity.to_i,
          entry_price: tracker.entry_price.to_f,
          exit_price: tracker.exit_price.to_f,
          status: tracker.status,
          pnl: tracker.last_pnl_rupees.to_f,
          pnl_pct: tracker.last_pnl_pct.to_f,
          segment: tracker.segment,
          paper: tracker.paper?,
          entry_strategy: tracker.entry_strategy,
          created_at: tracker.created_at.iso8601,
          exited_at: tracker.exited_at&.iso8601
        }
      end

      render json: { success: true, orders: orders }
    end
  end
end
