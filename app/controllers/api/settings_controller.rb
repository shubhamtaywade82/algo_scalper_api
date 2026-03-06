# frozen_string_literal: true

module Api
  class SettingsController < ApplicationController
    # GET /api/settings
    def index
      config = AlgoConfig.fetch

      # Separate top-level keys for easy categories
      render json: { success: true, config: config }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] index error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings
    # Requires a param `settings` containing the full updated config object
    def update_bulk
      new_config = params.require(:settings).permit!.to_h

      Setting.put('algo_config_overrides', new_config.to_json)
      AlgoConfig.reset!

      render json: { success: true, message: "Algo settings updated successfully" }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_bulk error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
