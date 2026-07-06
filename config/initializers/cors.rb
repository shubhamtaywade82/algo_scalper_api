# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

# In production, this API can place real trades — restrict CORS to known dashboard
# origin(s) via CORS_ALLOWED_ORIGINS (comma-separated) rather than wildcarding "*".
# Falls back to "*" with a boot-time warning if unset, so deploys aren't silently
# broken while CORS_ALLOWED_ORIGINS is being configured.
allowed_origins =
  if Rails.env.production?
    configured = ENV["CORS_ALLOWED_ORIGINS"].to_s.split(",").map(&:strip).compact_blank
    if configured.empty?
      Rails.logger.warn("[CORS] CORS_ALLOWED_ORIGINS not set in production — falling back to '*' (tighten this)")
      "*"
    else
      configured
    end
  else
    "*"
  end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins allowed_origins

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
