# frozen_string_literal: true

module Api
  # POST /api/strategies/:strategy_slug/deployment — scan + version + activate via Strategies::DeployPipeline.
  class StrategyDeploymentsController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::StrategyScoped

    before_action :authenticate_dashboard_token!

    def create
      slug = strategy_slug
      result = ::Strategies::DeployPipeline.call(slug)

      if result[:ok]
        render json: { success: true, version: serialize_version(result[:version]), scan_report: result[:scan_report] }
      else
        render json: { success: false, errors: result[:errors], scan_report: result[:scan_report] },
               status: :unprocessable_content
      end
    rescue ::Strategies::SlugValidator::InvalidSlug => e
      render json: { success: false, errors: [e.message] }, status: :unprocessable_content
    end
  end
end
