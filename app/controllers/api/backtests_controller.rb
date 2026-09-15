# frozen_string_literal: true

module Api
  class BacktestsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    MAX_DAYS_BACK = 365
    DEFAULT_DAYS = 30

    def show
      state = Rails.cache.read(EquityBacktestJob.cache_key(params.expect(:id)))
      return render json: { status: 'not_found' }, status: :not_found unless state

      render json: state
    end
    def create
      symbol = params[:symbol].to_s.upcase.presence || 'NIFTY'
      days_back = [params[:days_back].to_i.clamp(1, MAX_DAYS_BACK), DEFAULT_DAYS].max
      interval = params[:interval].presence || '5'

      run_id = SecureRandom.uuid
      Rails.cache.write(EquityBacktestJob.cache_key(run_id), { status: 'queued' }, expires_in: EquityBacktestJob::CACHE_EXPIRY)
      EquityBacktestJob.perform_later(run_id, symbol: symbol, interval: interval, days_back: days_back)

      render json: { backtest_run_id: run_id, status: 'queued' }, status: :accepted
    end
  end
end
