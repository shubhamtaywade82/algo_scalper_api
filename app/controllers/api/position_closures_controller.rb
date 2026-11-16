# frozen_string_literal: true

module Api
  # POST /api/positions/:position_id/closure — manual exit through Positions::ManualCloseService.
  class PositionClosuresController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def create
      outcome = Positions::ManualCloseService.call(tracker_id: params[:position_id])
      render json: outcome[:json], status: outcome[:status]
    end
  end
end
