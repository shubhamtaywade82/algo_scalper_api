# frozen_string_literal: true

module Api
  class SettingChangeLogsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/settings/change_logs — paginated audit trail.
    def index
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
      Rails.logger.error("[SettingChangeLogsController] index error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
