# frozen_string_literal: true

module Api
  # Algo config read/update API.
  # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
  class SettingsController < ApplicationController
    # Top-level keys allowed for algo config overrides (must match config/algo.yml structure)
    PERMITTED_SETTINGS_KEYS = %i[
      paper_trading trading_time_restrictions feature_flags indices trade_limits
      broker_fees risk position_sizing signals chain_analyzer option_chain
      data_freshness watchlist telegram ai
    ].freeze

    before_action :authenticate_settings!, only: :update_bulk

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
    # Requires a param `settings` containing the full updated config object.
    # Only top-level keys in PERMITTED_SETTINGS_KEYS are accepted.
    # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
    def update_bulk
      # rubocop:disable Rails/StrongParametersExpect -- dynamic allowlist from PERMITTED_SETTINGS_KEYS
      permitted = params.require(:settings).permit(PERMITTED_SETTINGS_KEYS.index_with { {} })
      # rubocop:enable Rails/StrongParametersExpect
      new_config = permitted.to_h.deep_symbolize_keys

      Setting.put('algo_config_overrides', new_config.to_json)
      AlgoConfig.reset!

      render json: { success: true, message: "Algo settings updated successfully" }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_bulk error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    private

    def authenticate_settings!
      expected = ENV['SETTINGS_UPDATE_TOKEN'].presence
      return if expected.nil?

      provided = request.headers['X-Settings-Update-Token'].presence || params[:token].presence
      return if provided && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      render json: { error: 'unauthorized' }, status: :unauthorized
    end
  end
end
