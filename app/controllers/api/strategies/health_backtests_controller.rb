# frozen_string_literal: true

module Api
  module Strategies
    class HealthBacktestsController < ApplicationController
      include Api::TokenAuthenticatable

      before_action :authenticate_dashboard_token!

      # GET /api/strategies/health/backtest
      def show
        render json: {
          success: true,
          backtests: {
            available: defined?(Backtest::Engine)
          }
        }
      end
    end
  end
end
