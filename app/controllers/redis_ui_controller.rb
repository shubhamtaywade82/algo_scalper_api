# frozen_string_literal: true

# Redis UI Controller - Development only
# Provides a simple web interface to browse and manage Redis keys
# NOTE: Inherits from ActionController::Base (not API) to support HTML views
# rubocop:disable Rails/ApplicationController, Metrics/ClassLength
class RedisUiController < ActionController::Base
  # Only allow in development
  before_action :ensure_development
  before_action :init_redis

  def index
    @pattern = params[:pattern] || '*'
    @db = params[:db] || '0'
    @cursor = (params[:cursor] || 0).to_i

    begin
      result = redis_inspector.scan(
        pattern: @pattern,
        db: @db,
        cursor: @cursor
      )

      @keys = result[:keys]
      @next_cursor = result[:next_cursor]
      @has_more = result[:has_more]
    rescue StandardError => e
      @error = e.message
      Rails.logger.error("[RedisUI] Error: #{e.class} - #{e.message}")
    end

    if request.format.json?
      render json: {
        pattern: @pattern,
        db: @db,
        keys: @keys,
        cursor: @cursor,
        next_cursor: @next_cursor,
        has_more: @has_more,
        error: @error
      }
    else
      # Render HTML view (requires ActionView to be enabled)
      render 'redis_ui/index', layout: false
    end
  end

  def show
    @key = params[:id]
    @db = params[:db] || '0'

    begin
      render json: redis_inspector.fetch(key: @key, db: @db)
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_content
    end
  end

  def destroy
    @key = params[:id]
    @db = params[:db] || '0'

    begin
      redis_inspector.delete(key: @key, db: @db)
      render json: { success: true, message: "Key '#{@key}' deleted" }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_content
    end
  end

  def info
    render json: { info: redis_inspector.info }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def ensure_development
    return if Rails.env.development?

    render json: { error: 'Redis UI is only available in development' }, status: :forbidden
  end

  def init_redis
    redis_url = ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')
    @redis = Redis.new(url: redis_url)
  rescue StandardError => e
    render json: { error: "Failed to connect to Redis: #{e.message}" }, status: :service_unavailable
  end

  def redis_inspector
    @redis_inspector ||= ::RedisUi::Inspector.new(client: @redis)
  end
end
# rubocop:enable Rails/ApplicationController, Metrics/ClassLength
