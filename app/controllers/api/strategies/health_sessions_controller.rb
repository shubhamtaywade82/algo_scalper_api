# frozen_string_literal: true

module Api
  module Strategies
    class HealthSessionsController < ApplicationController
      include Api::TokenAuthenticatable

      before_action :authenticate_dashboard_token!

      # GET /api/strategies/health/session
      def show
        render json: {
          success: true,
          market_open: ::TradingSession::Service.market_open?,
          in_session: ::TradingSession::Service.in_session?,
          entry_allowed: ::TradingSession::Service.entry_allowed?
        }
      end
    end
  end
end
