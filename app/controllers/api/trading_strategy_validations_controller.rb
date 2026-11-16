# frozen_string_literal: true

module Api
  # POST /api/trading_strategies/:trading_strategy_id/validation — runs the strategy's checks.
  class TradingStrategyValidationsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def create
      trading_strategy = TradingStrategy.find(params.expect(:trading_strategy_id))
      result = trading_strategy.run_checks!
      render json: {
        checks: result[:checks],
        backtest_results: result[:backtest_results],
        scan_report: result[:scan_report],
        strategy: trading_strategy
      }
    end
  end
end
