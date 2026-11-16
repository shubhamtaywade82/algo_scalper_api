# frozen_string_literal: true

module Api
  # POST   /api/circuit_breaker/trip → trip the breaker (blocks entries, force-closes positions)
  # DELETE /api/circuit_breaker/trip → reset the breaker (re-enables trading)
  #
  # The token is accepted ONLY via the X-Circuit-Breaker-Token header (never a query param)
  # so it cannot leak into access logs, browser history or proxy Referer headers.
  class CircuitBreakerTripsController < ApplicationController
    before_action :authenticate!

    def create
      reason = params[:reason].presence || 'manual API trigger'
      result = Risk::CircuitBreaker.instance.trip!(reason: reason)
      Rails.logger.warn("[CircuitBreakerTripsController] Tripped via API: #{reason} (from #{request.remote_ip})")
      render json: result, status: :ok
    end

    def destroy
      Risk::CircuitBreaker.instance.reset!
      Rails.logger.info("[CircuitBreakerTripsController] Reset via API (from #{request.remote_ip})")
      render json: { tripped: false, reset: true }, status: :ok
    end

    private

    def authenticate!
      expected = ENV['CIRCUIT_BREAKER_TOKEN'].presence
      provided = request.headers['X-Circuit-Breaker-Token'].presence

      return if expected && provided && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      render json: { error: 'unauthorized' }, status: :unauthorized
    end
  end
end
