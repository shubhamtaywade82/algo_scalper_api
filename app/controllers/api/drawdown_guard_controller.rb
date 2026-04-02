# frozen_string_literal: true

module Api
  class DrawdownGuardController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_operator_token!

    def reset
      Rails.logger.info(
        "[DrawdownGuardController] Reset requested: " \
        "IP=#{request.remote_ip}, UserAgent=#{request.user_agent}"
      )
      Portfolio::DrawdownGuard.reset_day!

      # Clear the PnL tracker peak as well so it can start fresh
      Portfolio::PnlTracker.reset_day!

      render json: { success: true, message: 'Drawdown guard reset successfully. Trading resumed.' }
    rescue StandardError => e
      Rails.logger.error("[DrawdownGuardController] Reset failed: #{e.message}")
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end
end
