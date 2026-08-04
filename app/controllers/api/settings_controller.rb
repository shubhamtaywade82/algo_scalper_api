# frozen_string_literal: true

module Api
  # Algo config read/update API.
  # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
  class SettingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: %i[index change_logs]
    before_action :authenticate_operator_token!, only: :update_ip
    before_action :authenticate_settings!, only: %i[update_bulk update_deep_merge]

    # Top-level keys allowed for algo config overrides (derived from document minus credentials).
    def self.permitted_settings_keys
      AlgoConfig.permitted_settings_keys
    end

    def self.permitted_settings_structure
      AlgoConfig.permitted_settings_structure
    end

    # Strong params: allow arbitrary nested hashes under each whitelisted top-level key only.
    PERMITTED_SETTINGS_STRUCTURE = PERMITTED_SETTINGS_KEYS.index_with { {} }.freeze

    # GET /api/settings
    def index
      config = AlgoConfig.fetch

      # Separate top-level keys for easy categories
      render json: { success: true, config: config }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] index error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/bulk
    # Param +settings+: only PERMITTED_SETTINGS_KEYS. Each **present** key replaces that entire top-level subtree
    # in +algo_config_document+; omitted keys are unchanged.
    # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
    def update_bulk
      # Permit only whitelisted top-level keys; each may carry a nested hash (full subtree replace).
      # rubocop:disable Rails/StrongParametersExpect -- require+permit keeps nesting and bad_request handling explicit
      raw = params.require(:settings).permit(PERMITTED_SETTINGS_STRUCTURE).to_h
      # rubocop:enable Rails/StrongParametersExpect
      new_config = raw.deep_symbolize_keys.compact

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

    def update_ip
      ip = params[:ip].presence || DhanHQ::Utils::NetworkInspector.public_ipv4
      result = Dhan::IpService.update_ip(ip)

      if result[:success]
        render json: { success: true, flag: result[:flag] }
      else
        render json: { success: false, error: result[:error] }, status: :unprocessable_entity
      end
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :internal_server_error
    end

    private

    def authenticate_settings!
      return if Rails.env.development?

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
