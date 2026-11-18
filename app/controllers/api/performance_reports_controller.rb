# frozen_string_literal: true

module Api
  # GET /api/reports/performance
  class PerformanceReportsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::ReportDateRange

    before_action :authenticate_dashboard_token!

    def show
      scope = date_filtered_scope(PositionTracker.exited)

      render json: { success: true }.merge(Reports::PerformanceSummary.new(scope).call)
    end
  end
end
