class HealthController < ActionController::API
  def ready
    # quick checks: db, redis, and required config
    healthy = true
    errors = []

    begin
      ActiveRecord::Base.connection.execute('SELECT 1')
    rescue StandardError => e
      healthy = false
      errors << "db:#{e.message}"
    end

    begin
      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      redis.ping
    rescue StandardError => e
      healthy = false
      errors << "redis:#{e.message}"
    end

    if healthy
      render json: { status: 'ok' }, status: :ok
    else
      render json: { status: 'fail', errors: errors }, status: :service_unavailable
    end
  end

  def live
    render json: { status: 'alive' }, status: :ok
  end
end
