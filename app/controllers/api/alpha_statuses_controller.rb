# frozen_string_literal: true

module Api
  # The dashboard's Alpha page is a view into the Strategies::Manager plugin platform
  # (Strategies::Record/Signal); there is no separate alpha signal engine.
  class AlphaStatusesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/alpha/status
    def show
      limits = AlgoConfig.fetch[:risk_limits] || {}

      render json: {
        enabled: ::Strategies::Record.where(desired_status: "running").exists?,
        indices: %w[nifty banknifty sensex],
        strategies: ::Strategies::Record.order(:slug).pluck(:slug),
        risk_stats: Risk::LimitsGuard.current_stats,
        risk_limits: {
          daily_max_trades: limits[:daily_max_trades] || 10,
          max_consecutive_losses: limits[:max_consecutive_losses] || 3,
          max_open_positions: limits[:max_open_positions] || 3
        }
      }
    rescue StandardError => e
      Rails.logger.error("[AlphaStatusesController] error: #{e.class} - #{e.message}")
      render json: { error: "internal_error" }, status: :internal_server_error
    end
  end
end
