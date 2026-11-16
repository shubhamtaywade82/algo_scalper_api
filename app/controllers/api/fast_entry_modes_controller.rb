# frozen_string_literal: true

module Api
  # Toggle for Signal::FastEntryMode (signals.fast_entry_mode.enabled in the algo config).
  class FastEntryModesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: :show
    before_action :authenticate_settings_token!, only: :update

    # GET /api/settings/fast_entry_mode
    def show
      render json: { success: true, fast_entry_mode: Signal::FastEntryMode.status }
    rescue StandardError => e
      Rails.logger.error("[FastEntryModesController] show error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # PATCH /api/settings/fast_entry_mode
    # Requires a param `enabled` (boolean).
    def update
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
      Rails.logger.error("[FastEntryModesController] update error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
