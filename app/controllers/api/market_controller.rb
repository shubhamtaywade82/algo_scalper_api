# frozen_string_literal: true

module Api
  class MarketController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/market/vix — read-only India VIX snapshot for dashboard tooling.
    def vix
      ltp = Market::VixGate.current_ltp
      render json: {
        vix: ltp&.to_f,
        evaluated: Market::VixGate.evaluated?,
        entry_allowed: Market::VixGate.entry_allowed?,
        force_exit_active: Market::VixGate.force_exit_active?
      }
    end
  end
end
