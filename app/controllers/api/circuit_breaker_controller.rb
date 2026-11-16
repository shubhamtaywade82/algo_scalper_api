# frozen_string_literal: true

module Api
  # Emergency circuit breaker API.
  #
  # All mutating endpoints require the X-Circuit-Breaker-Token header to match
  # the CIRCUIT_BREAKER_TOKEN environment variable. The token is accepted ONLY
  # via header (never via query param) so it does not leak into access logs,
  # browser history, or proxy Referer headers.
  #
  # GET /api/circuit_breaker → current status (unauthenticated).
  # Tripping and resetting live in CircuitBreakerTripsController.
  class CircuitBreakerController < ApplicationController
    def show
      render json: Risk::CircuitBreaker.instance.status
    end
  end
end
