# frozen_string_literal: true

module Api
  # Historical options behaviour for an index (HistoricalOptionsAnalyzer).
  class AnalysisHistoriesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/analysis/:index_key/history
    def show
      index_key = params[:index_key].to_s.upcase
      weeks = (params[:weeks] || 8).to_i.clamp(1, 24)

      analyzer = HistoricalOptionsAnalyzer.new(index_key, weeks: weeks)
      result = analyzer.analyze

      render json: result
    rescue StandardError => e
      Rails.logger.error("[AnalysisHistoriesController] error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error', message: e.message }, status: :internal_server_error
    end
  end
end
