# frozen_string_literal: true

# Middleware that injects a correlation ID into every request and log context.
# The ID is generated if not present, and set as the `X-Request-ID` header
# in the response. All structured logs within the request automatically
# include this correlation ID for distributed tracing.
class CorrelationIdMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request_id = extract_or_generate_id(env)
    env['HTTP_X_REQUEST_ID'] = request_id

    # Set for structured logging and ActionCable
    Thread.current[:correlation_id] = request_id

    # Set log context
    Rails.application.config.log_tags ||= []
    # Add correlation_id to log context if not already present
    Thread.current[:request_id] = request_id

    status, headers, body = @app.call(env)

    headers['X-Request-Id'] = request_id

    [status, headers, body]
  ensure
    Thread.current[:correlation_id] = nil
    Thread.current[:request_id] = nil
  end

  private

  def extract_or_generate_id(env)
    # Use existing X-Request-ID from client if present
    request_id = env['HTTP_X_REQUEST_ID']
    return request_id if request_id.present? && request_id.length <= 128

    # Generate a new one
    SecureRandom.uuid
  end
end

Rails.application.config.middleware.insert_before 0, CorrelationIdMiddleware
