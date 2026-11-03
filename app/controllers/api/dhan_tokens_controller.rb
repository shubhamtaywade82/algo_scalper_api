# frozen_string_literal: true

module Api
  # Shares this app's live Dhan access token with other local tools, so they reuse it instead of
  # generating their own — generating a token invalidates every other holder (DH-906).
  #
  #   GET /api/dhan/token   → { access_token, expires_at, client_id }
  #
  # The token can place live orders, so unlike the dashboard endpoints this is never open:
  # API_OPERATOR_TOKEN must be configured and presented, in every environment.
  class DhanTokensController < ApplicationController
    include Api::TokenAuthenticatable

    def show
      expected = ENV['API_OPERATOR_TOKEN'].presence
      return render json: { error: 'operator_token_not_configured' }, status: :service_unavailable unless expected
      return render json: { error: 'unauthorized' }, status: :unauthorized unless token_matches?(provided_api_token, expected)

      snapshot = Dhan::TokenManager.snapshot
      return render json: { error: 'token_unavailable' }, status: :service_unavailable unless snapshot

      response.headers['Cache-Control'] = 'no-store'
      render json: {
        access_token: snapshot[:token],
        expires_at: snapshot[:expiry_time].iso8601,
        client_id: snapshot[:client_id]
      }
    end
  end
end
