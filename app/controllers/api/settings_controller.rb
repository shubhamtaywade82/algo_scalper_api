# frozen_string_literal: true

module Api
  # Algo config read/update API.
  # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
  class SettingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: %i[index change_logs]
    before_action :authenticate_operator_token!, only: :update_ip
    before_action :authenticate_settings!, only: %i[update_bulk update_deep_merge update_fast_entry_mode]

    # Top-level keys allowed for algo config overrides (derived from document minus credentials).
    def self.permitted_settings_keys
      AlgoConfig.permitted_settings_keys
    end

    def self.permitted_settings_structure
      AlgoConfig.permitted_settings_structure
    end

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
      raw = params.require(:settings).permit(self.class.permitted_settings_structure).to_h
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
    rescue AlgoConfig::ValidationError => e
      Rails.logger.warn("[SettingsController] update_bulk rejected invalid config: #{e.message}")
      render json: { error: 'invalid_config', errors: e.errors }, status: :unprocessable_content
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_bulk error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/deep_merge
    # Param +patch+: a nested hash representing the subset of config to update.
    # Applies deep merge so omitted keys are untouched.
    def update_deep_merge
      # Permit only whitelisted top-level keys allowing arbitrary sub-structures.
      # rubocop:disable Rails/StrongParametersExpect
      raw_patch = params.require(:patch).permit(self.class.permitted_settings_structure).to_h
      # rubocop:enable Rails/StrongParametersExpect
      patch_config = raw_patch.deep_symbolize_keys.compact

      if patch_config.blank?
        render json: { success: false, error: 'No permitted patch keys provided' }, status: :unprocessable_content
        return
      end

      AlgoConfig::DocumentStore.apply_deep_merge_patch!(
        patch_config,
        source: 'api_settings_deep_merge',
        actor: 'api',
        request_id: request.request_id,
        metadata: { remote_ip: request.remote_ip }
      )

      render json: { success: true, message: 'Settings modified successfully' }
    rescue ActionController::ParameterMissing => e
      Rails.logger.warn("[SettingsController] update_deep_merge missing params: #{e.message}")
      render json: { error: e.message }, status: :bad_request
    rescue AlgoConfig::ValidationError => e
      Rails.logger.warn("[SettingsController] update_deep_merge rejected invalid config: #{e.message}")
      render json: { error: 'invalid_config', errors: e.errors }, status: :unprocessable_content
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_deep_merge error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # GET /api/settings/fast_entry_mode
    def fast_entry_mode
      render json: { success: true, fast_entry_mode: Signal::FastEntryMode.status }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] fast_entry_mode error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/fast_entry_mode
    # Body: { "enabled": true|false } — persisted to algo_config_document; effective immediately (no daemon restart).
    # FAST_ENTRY_MODE env, when set, overrides the DB value until removed and process restarted.
    def update_fast_entry_mode
      enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))

      AlgoConfig::DocumentStore.apply_deep_merge_patch!(
        { signals: { fast_entry_mode: { enabled: enabled } } },
        source: 'api_fast_entry_mode',
        actor: 'api',
        request_id: request.request_id,
        metadata: { remote_ip: request.remote_ip, enabled: enabled }
      )

      render json: {
        success: true,
        message: enabled ? 'Fast entry mode enabled' : 'Fast entry mode disabled',
        fast_entry_mode: Signal::FastEntryMode.status
      }
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue AlgoConfig::ValidationError => e
      render json: { error: 'invalid_config', errors: e.errors }, status: :unprocessable_content
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_fast_entry_mode error: #{e.class} - #{e.message}")
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

    def update_ip
      ip = params[:ip].presence || DhanHQ::Utils::NetworkInspector.public_ipv4
      result = Dhan::IpService.update_ip(ip)

      if result[:success]
        render json: { success: true, flag: result[:flag] }
      else
        render json: { success: false, error: result[:error] }, status: :unprocessable_content
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
