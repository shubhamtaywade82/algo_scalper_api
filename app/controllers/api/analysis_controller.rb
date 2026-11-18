# frozen_string_literal: true

module Api
  class AnalysisController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/analysis/:index_key
    # Always returns instantly from cache. Triggers background refresh if stale.
    def show
      index_key = params[:index_key].to_s.upcase
      instrument = IndexConfigLoader.index_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      overview = Analysis::IndexOverview.new(index_key: index_key, instrument: instrument)
      refresh_in_background(index_key, overview.stale_components)

      render json: overview.to_h
    rescue StandardError => e
      Rails.logger.error("[AnalysisController] show error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error', message: e.message }, status: :internal_server_error
    end

    private

    def refresh_in_background(index_key, stale_components)
      return if stale_components.empty?

      force = params[:force] == 'true'
      Thread.new do
        Rails.application.executor.wrap { AnalysisJob.perform_now(index_key, force: force) }
      end
    end
  end
end
