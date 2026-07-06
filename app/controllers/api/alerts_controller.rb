# frozen_string_literal: true

module Api
  class AlertsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      # Alerts CRUD tables are not in schema; return empty/stub response so UI doesn't error
      render json: []
    end
  end
end
