# frozen_string_literal: true

module Api
  module Strategies
    class HealthPoolsController < ApplicationController
      include Api::TokenAuthenticatable

      before_action :authenticate_dashboard_token!

      # GET /api/strategies/health/pool
      def show
        manager = find_manager
        all = manager&.all_statuses || {}

        render json: {
          success: true,
          running: all.values.count { |s| s[:status] == "running" },
          total: all.size,
          runners: all
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
