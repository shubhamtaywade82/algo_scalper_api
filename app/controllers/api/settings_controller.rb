# frozen_string_literal: true

module Api
  # Algo config read/update API.
  # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
  class SettingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: :index
    before_action :authenticate_settings!, only: :update_bulk

    # Top-level keys allowed for algo config overrides (must match config/algo.yml structure)
    PERMITTED_SETTINGS_KEYS = %i[
      paper_trading trading_time_restrictions feature_flags indices trade_limits
      broker_fees risk position_sizing signals chain_analyzer option_chain
      data_freshness watchlist telegram ai
    ].freeze

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
      raw = params.require(:settings).permit!.to_h
      allowed_keys = PERMITTED_SETTINGS_KEYS.map(&:to_s)
      new_config = raw.slice(*allowed_keys).deep_symbolize_keys

      if new_config.blank?
        render json: { success: false, error: 'No permitted settings keys provided' }, status: :unprocessable_content
        return
      end

      AlgoConfig::DocumentStore.apply_top_level_replacements!(
        new_config,
        source: 'api_settings_bulk',
        actor: 'api',
        request_id: request.request_id,
        metadata: { remote_ip: request.remote_ip }
      )

      render json: { success: true, message: 'Algo settings updated successfully' }
    rescue ActionController::ParameterMissing => e
      Rails.logger.warn("[SettingsController] update_bulk missing params: #{e.message}")
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_bulk error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # GET /api/settings/change_logs — paginated audit trail.
    def change_logs
      limit = (params[:limit] || 50).to_i.clamp(1, 200)
      offset = [params[:offset].to_i, 0].max
      total = AlgoConfigChangeLog.count
      rows = AlgoConfigChangeLog.recent_first.limit(limit).offset(offset)

      render json: {
        success: true,
        total: total,
        limit: limit,
        offset: offset,
        change_logs: rows.as_json(only: %i[id source actor request_id patch changed_paths metadata created_at])
      }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] change_logs error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    private

    def authenticate_settings!
      if Rails.env.production? && ENV['SETTINGS_UPDATE_TOKEN'].blank?
        Rails.logger.error('[SettingsController] SETTINGS_UPDATE_TOKEN must be set in production for bulk updates')
        render json: { error: 'settings_update_unconfigured' }, status: :service_unavailable
        return
      end

      expected = ENV['SETTINGS_UPDATE_TOKEN'].presence
      return if expected.nil?

      provided = request.headers['X-Settings-Update-Token'].presence || params[:token].presence
      return if provided && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      render json: { error: 'unauthorized' }, status: :unauthorized
    end
  end
end
