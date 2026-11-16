# frozen_string_literal: true

module Api
  # Deployed versions of a strategy.
  class StrategyVersionsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::StrategyScoped

    before_action :authenticate_dashboard_token!
    before_action :find_strategy

    # GET /api/strategies/:strategy_slug/versions
    def index
      records = @strategy.versions.order(version: :desc).limit(50)
      render json: {
        success: true,
        versions: records.map { |v| serialize_version(v) }
      }
    end
  end
end
