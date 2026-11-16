# frozen_string_literal: true

module Api
  # Recent runner log lines for a strategy.
  class StrategyLogsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::StrategyScoped

    before_action :authenticate_dashboard_token!
    before_action :find_strategy

    # GET /api/strategies/:strategy_slug/logs
    def index
      limit = [params[:limit].to_i, 1].max
      limit = [limit, 1000].min

      entries = ::Strategies::LogStream.fetch(@strategy.slug, limit: limit)
      render json: { success: true, logs: entries }
    end
  end
end
