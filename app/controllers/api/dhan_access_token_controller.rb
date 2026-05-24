# frozen_string_literal: true

module Api
  class DhanAccessTokenController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def show
      token = Dhan::TokenManager.current_token
      record = DhanAccessToken.active

      if token
        render json: {
          dhanaccesstoken: token,
          dhan_access_token: token,
          expiry_time: record&.expiry_time&.iso8601
        }
      else
        render json: { error: 'token_not_found' }, status: :not_found
      end
    end
  end
end
