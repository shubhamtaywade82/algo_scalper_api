# frozen_string_literal: true

module Api
  class TradingStrategiesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!
    before_action :set_trading_strategy, only: %i[show update destroy validate deploy]

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
      render json: {
        checks: result[:checks],
        backtest_results: result[:backtest_results],
        scan_report: result[:scan_report],
        strategy: @trading_strategy
      }
    end

    # POST /api/trading_strategies/:id/deploy
    def deploy
      result = ::Strategies::AdHocDeployer.call(@trading_strategy)

      if result[:ok]
        render json: {
          success: true,
          slug: @trading_strategy.slug,
          strategy_record_id: @trading_strategy.strategy_record_id,
          scan_report: result[:scan_report],
          strategy: @trading_strategy
        }
      else
        render json: { success: false, errors: result[:errors], scan_report: result[:scan_report] },
               status: :unprocessable_content
      end
    end

    private

    def set_trading_strategy
      @trading_strategy = TradingStrategy.find(params.expect(:id))
    end

    def trading_strategy_params
      params.expect(trading_strategy: [%i[
                      name version status code description author
                      runtime timeframe trade_direction
                    ], {
                      instruments: [], tags: [], parameters: %i[name type default_value description],
                      entry_rules: {}, exit_rules: {}, risk_management: {}, filters: {}, schedule: {}
                    }])
    end
  end
end
