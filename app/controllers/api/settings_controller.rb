# frozen_string_literal: true

module Api
  # Algo config read/update API.
  #   GET   /api/settings  current config
  #   PUT   /api/settings  { settings: } replaces whole top-level sections
  #   PATCH /api/settings  { patch: }    deep-merges a nested patch
  # When SETTINGS_UPDATE_TOKEN is set, writes require the X-Settings-Update-Token header.
  class SettingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: :show
    before_action :authenticate_settings_token!, only: :update

    # Top-level keys allowed for algo config overrides (must match config/algo.yml structure).
    # dhanhq (enable_orders live gate), run_mode, ledger and realtime stay YAML-only on purpose.
    PERMITTED_SETTINGS_KEYS = %i[
      paper_trading trading_time_restrictions feature_flags indices trade_limits
      broker_fees risk position_sizing signals chain_analyzer option_chain
      data_freshness watchlist telegram ai midday_guard loss_streak_guard market_context
      entry_quality profit_lock smc expiry_week_power_trend sizing
    ].freeze

    # GET /api/settings
    def show
      config = AlgoConfig.fetch

      # Separate top-level keys for easy categories
      render json: { success: true, config: config }
    rescue StandardError => e
      Rails.logger.error("[SettingsController] show error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    def update
      request.put? ? replace_sections : deep_merge_patch
    end

    private

    # PUT: `settings` holds full top-level sections; only PERMITTED_SETTINGS_KEYS are accepted.
    def replace_sections
      # Full unfiltered read is intentional: authorization happens below against
      # PERMITTED_SETTINGS_KEYS (unknown top-level keys are rejected, not sliced).
      raw = params.require(:settings).to_unsafe_h
      allowed_keys = PERMITTED_SETTINGS_KEYS.map(&:to_s)
      read_only_keys = raw.keys - allowed_keys
      # Silently slicing these off returned success while discarding the user's edits.
      if read_only_keys.any?
        render json: { success: false, error: "Read-only settings sections: #{read_only_keys.join(', ')}" },
               status: :unprocessable_content
        return
      end

      new_config = raw.deep_symbolize_keys

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
    rescue AlgoConfig::ValidationError => e
      render json: { success: false, error: e.message, errors: e.errors }, status: :unprocessable_content
    rescue ActionController::ParameterMissing => e
      Rails.logger.warn("[SettingsController] update_bulk missing params: #{e.message}")
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[SettingsController] update_bulk error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH: `patch` (nested hash) is deep-merged into the algo config document.
    # Only top-level keys in PERMITTED_SETTINGS_KEYS are accepted; nested values within
    # an allowed key are merged in full (unlike PUT's top-level replacement).
    def deep_merge_patch
      # Full unfiltered read is intentional: only PERMITTED_SETTINGS_KEYS top-level
      # keys survive the slice below; nested values merge in full by design.
      patch = params.require(:patch).to_unsafe_h
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
    rescue AlgoConfig::ValidationError => e
      render json: { success: false, error: e.message, errors: e.errors }, status: :unprocessable_content
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[SettingsController] deep_merge error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
