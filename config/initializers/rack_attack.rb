# frozen_string_literal: true

# Per-IP rate limits for /api (expensive AI endpoint has a separate bucket).
# Disabled in test via +Rack::Attack.enabled = false+ after boot.
#
# Tune with env: +RACK_ATTACK_API_LIMIT+, +RACK_ATTACK_API_PERIOD_SECONDS+,
# +RACK_ATTACK_AI_LIMIT+, +RACK_ATTACK_AI_PERIOD_SECONDS+ (optional).

module Rack
  class Attack
    API_LIMIT = Integer(ENV.fetch('RACK_ATTACK_API_LIMIT', '240'))
    API_PERIOD = Integer(ENV.fetch('RACK_ATTACK_API_PERIOD_SECONDS', '300'))
    AI_LIMIT = Integer(ENV.fetch('RACK_ATTACK_AI_LIMIT', '12'))
    AI_PERIOD = Integer(ENV.fetch('RACK_ATTACK_AI_PERIOD_SECONDS', '60'))

    safelist('healthcheck') { |req| req.path == '/up' }

    safelist('well-known') { |req| req.path.start_with?('/.well-known') }

    throttle('api/ip', limit: API_LIMIT, period: API_PERIOD) do |req|
      req.ip if req.path.start_with?('/api')
    end

    throttle('api/ai_snapshot/ip', limit: AI_LIMIT, period: AI_PERIOD) do |req|
      req.ip if req.post? && req.path.match?(%r{\A/api/analysis/[^/]+/ai_snapshot\z})
    end

    self.throttled_responder = lambda { |_req|
      [429, { 'Content-Type' => 'application/json' }, ['{"error":"rate_limited"}']]
    }
  end
end

Rails.application.config.middleware.use Rack::Attack

Rails.application.config.after_initialize do
  Rack::Attack.enabled = !Rails.env.test?
  Rack::Attack.cache.store = Rails.cache
end
