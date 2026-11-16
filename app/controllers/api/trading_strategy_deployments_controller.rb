# frozen_string_literal: true

module Api
  # POST /api/trading_strategies/:trading_strategy_id/deployment — deploys via Strategies::AdHocDeployer.
  class TradingStrategyDeploymentsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def create
      trading_strategy = TradingStrategy.find(params.expect(:trading_strategy_id))
      result = ::Strategies::AdHocDeployer.call(trading_strategy)

      if result[:ok]
        render json: {
          success: true,
          slug: trading_strategy.slug,
          strategy_record_id: trading_strategy.strategy_record_id,
          scan_report: result[:scan_report],
          strategy: trading_strategy
        }
      else
        render json: { success: false, errors: result[:errors], scan_report: result[:scan_report] },
               status: :unprocessable_content
      end
    end
  end
end
