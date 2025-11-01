# frozen_string_literal: true

module Api
  class TestController < ApplicationController
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
  end
end
