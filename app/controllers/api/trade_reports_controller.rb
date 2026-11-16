# frozen_string_literal: true

module Api
  # GET /api/reports/trades
  class TradeReportsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::ReportDateRange

    before_action :authenticate_dashboard_token!

    def index
      scope = date_filtered_scope(PositionTracker.exited.includes(:watchable, :instrument))
              .order(params[:sort] == 'pnl_desc' ? { last_pnl_rupees: :desc } : { exited_at: :desc })

      scope = scope.where(side: params.expect(:side).upcase) if params[:side].present?

      page = [params[:page].to_i, 1].max
      per_page = [params[:per_page].to_i, 1].max
      per_page = [per_page, 100].min

      total = scope.count
      total_pages = [1, (total.to_f / per_page).ceil].max
      page = [page, total_pages].min
      offset = (page - 1) * per_page

      trades = scope.offset(offset).limit(per_page).map do |tracker|
        Positions::Serializer.closed(tracker)
      end

      render json: {
        success: true,
        trades: trades,
        meta: { total: total, page: page, per_page: per_page, pages: total_pages }
      }
    end
  end
end
