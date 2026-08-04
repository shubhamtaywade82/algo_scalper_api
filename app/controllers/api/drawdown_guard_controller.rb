# frozen_string_literal: true

module Api
  class DrawdownGuardController < ApplicationController
    def reset
      Portfolio::DrawdownGuard.reset_day!
      
      # Clear the PnL tracker peak as well so it can start fresh
      Portfolio::PnlTracker.reset_day!

      render json: { success: true, message: 'Drawdown guard reset successfully. Trading resumed.' }
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end
end
