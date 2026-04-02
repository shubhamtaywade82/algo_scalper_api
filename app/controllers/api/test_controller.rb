# frozen_string_literal: true

module Api
  class TestController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :ensure_test_broadcast_allowed!

    def broadcast
      tick_data = {
        segment: params[:segment] || 'IDX_I',
        security_id: params[:security_id] || '13',
        ltp: params[:ltp] || rand(25_000..25_999),
        kind: :quote,
        ts: Time.current.to_i
      }

      # Store in TickCache instead of broadcasting
      Live::TickCache.put(tick_data)

      render json: {
        success: true,
        message: 'Test tick stored in TickCache',
        data: tick_data
      }
    end

    private

    def ensure_test_broadcast_allowed!
      return if Rails.env.local?

      expected = ENV['API_OPERATOR_TOKEN'].presence
      unless expected
        Rails.logger.warn('[Api::TestController] test_broadcast blocked outside development (set API_OPERATOR_TOKEN)')
        render json: { error: 'forbidden' }, status: :forbidden
        return
      end

      authenticate_operator_token!
    end
  end
end
