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
    @keys = []
    @cursor = (params[:cursor] || 0).to_i
    @page_size = 100

    begin
      # Switch to selected database
      @redis.select(@db.to_i)

      # Scan keys with pattern
      cursor, keys = @redis.scan(@cursor, match: @pattern, count: @page_size)
      @keys = keys.map do |key|
        {
          key: key,
          type: @redis.type(key),
          ttl: @redis.ttl(key),
          size: get_key_size(key)
        }
      end
      @next_cursor = cursor.to_i
      @has_more = @next_cursor != 0
    rescue StandardError => e
      @error = e.message
      Rails.logger.error("[RedisUI] Error: #{e.class} - #{e.message}")
    end

    # Return JSON if JSON format requested, otherwise render HTML view
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
      @redis.select(@db.to_i)

      key_type = @redis.type(@key)
      value = get_key_value(@key, key_type)
      ttl = @redis.ttl(@key)

      render json: {
        key: @key,
        type: key_type,
        ttl: ttl,
        value: value,
        size: get_key_size(@key)
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def destroy
    @key = params[:id]
    @db = params[:db] || '0'

    begin
      @redis.select(@db.to_i)

      @redis.del(@key)
      render json: { success: true, message: "Key '#{@key}' deleted" }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def info
    info_data = @redis.info
    render json: { info: info_data }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  def get_key_value(key, type)
    case type
    when 'string'
      @redis.get(key)
    when 'hash'
      @redis.hgetall(key)
    when 'list'
      @redis.lrange(key, 0, -1)
    when 'set'
      @redis.smembers(key)
    when 'zset'
      @redis.zrange(key, 0, -1, with_scores: true)
    else
      'Unknown type'
    end
  end

  def get_key_size(key)
    type = @redis.type(key)
    case type
    when 'string'
      @redis.strlen(key)
    when 'hash'
      @redis.hlen(key)
    when 'list'
      @redis.llen(key)
    when 'set'
      @redis.scard(key)
    when 'zset'
      @redis.zcard(key)
    else
      0
    end
  end
end
# rubocop:enable Rails/ApplicationController, Metrics/ClassLength
