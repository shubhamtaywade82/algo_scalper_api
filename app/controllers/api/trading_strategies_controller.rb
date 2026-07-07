# frozen_string_literal: true

module Api
  class TradingStrategiesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!
    before_action :set_trading_strategy, only: %i[show update destroy validate]

    # GET /api/trading_strategies
    def index
      strategies = TradingStrategy.order(updated_at: :desc)
      render json: strategies
    end

    # GET /api/trading_strategies/:id
    def show
      render json: @trading_strategy
    end

    # POST /api/trading_strategies
    def create
      strategy = TradingStrategy.new(trading_strategy_params)

      if strategy.save
        render json: strategy, status: :created
      else
        render json: { errors: strategy.errors.full_messages }, status: :unprocessable_content
      end
    end

    # PATCH/PUT /api/trading_strategies/:id
    def update
      if @trading_strategy.update(trading_strategy_params)
        render json: @trading_strategy
      else
        render json: { errors: @trading_strategy.errors.full_messages }, status: :unprocessable_content
      end
    end

    # DELETE /api/trading_strategies/:id
    def destroy
      @trading_strategy.update!(status: "archived")
      render json: @trading_strategy
    end

    # POST /api/trading_strategies/:id/validate
    def validate
      result = @trading_strategy.run_checks!
      render json: { checks: result[:checks], backtest_results: result[:backtest_results] }
    end

    private

    def set_trading_strategy
      @trading_strategy = TradingStrategy.find(params[:id])
    end

    def trading_strategy_params
      params.expect(trading_strategy: %i[
                      name version status code description author
                      runtime timeframe trade_direction parameters instruments tags
                    ])
    end
  end
end
