# frozen_string_literal: true

module Api
  # Desired run state of a strategy; Strategies::Manager reconciles it within ~2s.
  class StrategyRunsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::StrategyScoped

    before_action :authenticate_dashboard_token!
    before_action :find_strategy

    # POST /api/strategies/:strategy_slug/run — start
    def create
      @strategy.update!(desired_status: "running")
      render json: { success: true, slug: @strategy.slug, status: "starting" }, status: :accepted
    end

    # PATCH /api/strategies/:strategy_slug/run — restart
    def update
      @strategy.update!(desired_status: "stopped")
      @strategy.update!(desired_status: "running")
      render json: { success: true, slug: @strategy.slug, status: "restarting" }, status: :accepted
    end
    # DELETE /api/strategies/:strategy_slug/run — stop
    def destroy
      @strategy.update!(desired_status: "stopped")
      render json: { success: true, slug: @strategy.slug, status: "stopping" }, status: :accepted
    end
  end
end
