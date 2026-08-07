# frozen_string_literal: true

module Api
  module Strategies
    # Health and diagnostics for the strategy subsystem.
    class HealthController < ApplicationController
      include Api::TokenAuthenticatable

      before_action :authenticate_dashboard_token!

      # GET /api/strategies/health/pool
      def pool
        manager = find_manager
        all = manager&.all_statuses || {}

        render json: {
          success: true,
          running: all.values.count { |s| s[:status] == "running" },
          total: all.size,
          runners: all
        }
      end

      # GET /api/strategies/health/session
      def session
        render json: {
          success: true,
          market_open: ::TradingSession::Service.market_open?,
          session: ::TradingSession::Service.current_session_info
        }
      end

      # GET /api/strategies/health/backtest
      def backtest
        render json: {
          success: true,
          backtests: {
            available: defined?(Backtest::Engine)
          }
        }
      end

      private

      def find_manager
        return nil unless defined?(::Strategies::Manager)

        ObjectSpace.each_object(::Strategies::Manager).first
      end
    end
  end
end
