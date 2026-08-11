# frozen_string_literal: true

module Api
  # Algo config read/update API.
  # When SETTINGS_UPDATE_TOKEN is set, PATCH requires header X-Settings-Update-Token or param token.
  class SettingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: %i[index fast_entry_mode]
    before_action :authenticate_settings!, only: %i[update_bulk update_fast_entry_mode update_ip deep_merge]

    # Top-level keys allowed for algo config overrides (must match config/algo.yml structure)
    PERMITTED_SETTINGS_KEYS = %i[
      paper_trading trading_time_restrictions feature_flags indices trade_limits
      broker_fees risk position_sizing signals chain_analyzer option_chain
      data_freshness watchlist telegram ai midday_guard loss_streak_guard market_context
      entry_quality
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

    # GET /api/settings/fast_entry_mode
    def fast_entry_mode
      render json: { success: true, fast_entry_mode: Signal::FastEntryMode.status }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] fast_entry_mode error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/fast_entry_mode
    # Requires a param `enabled` (boolean).
    def update_fast_entry_mode
      enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))

      AlgoConfig::DocumentStore.apply_deep_merge_patch!(
        { signals: { fast_entry_mode: { enabled: enabled } } },
        source: 'api_settings_fast_entry_mode',
        actor: 'api',
        request_id: request.request_id,
        metadata: { remote_ip: request.remote_ip }
      )
      Signal::FastEntryMode.reset!

      render json: { success: true, fast_entry_mode: Signal::FastEntryMode.status }
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_fast_entry_mode error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # POST /api/settings/update_ip
    # Detects the current public IPv4 and attempts to whitelist it on Dhan.
    def update_ip
      info = Dhan::IpService.fetch_ip_info
      ip = info[:public_ipv4]

      if ip.blank? || ip == 'Unknown'
        render json: { success: false, error: 'Could not detect current public IPv4' }
        return
      end

      render json: Dhan::IpService.update_ip(ip)
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_ip error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/deep_merge
    # Requires a param `patch` (nested hash) — deep-merged into the algo config document.
    # Only top-level keys in PERMITTED_SETTINGS_KEYS are accepted; nested values within
    # an allowed key are merged in full (unlike update_bulk's top-level replacement).
    def deep_merge
      patch = params.require(:patch).permit!.to_h
      allowed_keys = PERMITTED_SETTINGS_KEYS.map(&:to_s)
      filtered_patch = patch.slice(*allowed_keys)

      if filtered_patch.blank?
        render json: { success: false, error: 'No permitted settings keys provided' }, status: :unprocessable_content
        return
      end

      AlgoConfig::DocumentStore.apply_deep_merge_patch!(
        filtered_patch,
        source: 'api_settings_deep_merge',
        actor: 'api',
        request_id: request.request_id,
        metadata: { remote_ip: request.remote_ip }
      )

      render json: { success: true, message: 'Settings updated successfully' }
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[SettingsController] deep_merge error: #{e.class} - #{e.message}")
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
