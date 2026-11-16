# frozen_string_literal: true

module Api
  # GET /api/reports/market_brief/live — realtime facts (rebuilt per poll, 3s cache) plus
  # the latest validated AI commentary. Never calls the LLM, so it is safe to poll.
  class LiveMarketBriefsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def show
      render json: { success: true, **::Reports::MarketBrief::LiveBrief.call(mode: AlgoConfig.mode) }
    end
  end
end
