# frozen_string_literal: true

module Api
  # Emergency circuit breaker API.
  #
  # All mutating endpoints require the X-Circuit-Breaker-Token header to match
  # the CIRCUIT_BREAKER_TOKEN environment variable.
  #
  # GET    /api/circuit_breaker        → current status
  # POST   /api/circuit_breaker/trip   → trip the breaker (blocks entries, force-closes positions)
  # DELETE /api/circuit_breaker/trip   → reset the breaker (re-enables trading)
  class CircuitBreakerController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: :show
    before_action :authenticate!, only: %i[trip reset]

    def show
      render json: Risk::CircuitBreaker.instance.status
    end

    def trip
      reason = params[:reason].presence || 'manual API trigger'
      result = Risk::CircuitBreaker.instance.trip!(reason: reason)
      Rails.logger.warn("[CircuitBreakerController] Tripped via API: #{reason} (from #{request.remote_ip})")
      render json: result, status: :ok
    end

    def reset
      Risk::CircuitBreaker.instance.reset!
      Rails.logger.info("[CircuitBreakerController] Reset via API (from #{request.remote_ip})")
      render json: { tripped: false, reset: true }, status: :ok
    end

    private

    def authenticate!
      expected = ENV['CIRCUIT_BREAKER_TOKEN'].presence
      provided = request.headers['X-Circuit-Breaker-Token'].presence || params[:token].presence

      return if expected && provided && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      render json: { error: 'unauthorized' }, status: :unauthorized
    end
  end
end
