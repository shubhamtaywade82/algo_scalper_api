# frozen_string_literal: true

# GET /redis_ui/info — Redis INFO for the dev Redis UI. Reuses RedisUiController's
# development-only guard and connection; routes expose only #show here.
class RedisUiInfosController < RedisUiController
  def show
    render json: { info: @redis.info }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
