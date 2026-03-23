# frozen_string_literal: true

# Boot-time safety: ensure a valid Dhan token exists for long-running services.
# Uses ENV-based secrets (via dotenv in dev/test) and persists token in DB.
#
# Only run in the trading daemon process (ENABLE_TRADING_SERVICES=true).
# The web process must not block boot on token refresh; it gets the token
# lazily via the access_token_provider lambda when an API call needs it.
Rails.application.config.after_initialize do
  next if Rails.const_defined?(:Console)
  next if Rails.env.test?
  next if ENV['DISABLE_TRADING_SERVICES'] == '1'
  next unless ENV['ENABLE_TRADING_SERVICES'] == 'true'

  # Eager prefetch when token authority is configured (fail fast with clear error)
  base_url = ENV['TRADER_API_BASE_URL'].to_s.strip
  bearer = ENV['DHAN_TOKEN_ACCESS_TOKEN'].presence

  if base_url.present? && bearer.present?
    provider = DhanHQ.configuration.access_token_provider
    if provider.respond_to?(:call)
      begin
        provider.call
        Rails.logger.info('[SCALPER] Dhan token prefetched from authority server')
      rescue StandardError => e
        Rails.logger.error(
          "[SCALPER] Dhan token authority fetch failed: #{e.message}. " \
          "Check TRADER_API_BASE_URL and DHAN_TOKEN_ACCESS_TOKEN and that the authority server is running."
        )
      end
    end
  else
    hint_key = 'scalper:dhan_authority_hint_shown'
    unless Rails.cache.read(hint_key)
      msg = if bearer.present?
        "[SCALPER] To fetch Dhan token from your authority server, set TRADER_API_BASE_URL in .env " \
          "(base URL of the API that serves /auth/dhan/token). See .env.example."
            elsif base_url.present?
        "[SCALPER] To fetch Dhan token from your authority server, set DHAN_TOKEN_ACCESS_TOKEN in .env " \
          "(Bearer token you use in Postman for /auth/dhan/token). See .env.example."
            else
        "[SCALPER] To fetch Dhan token from an authority server (e.g. algo_trading_api), set TRADER_API_BASE_URL " \
          "and DHAN_TOKEN_ACCESS_TOKEN in .env. See .env.example."
            end
      Rails.logger.warn(msg)
      Rails.cache.write(hint_key, true, expires_in: 1.hour)
    end
  end

  # Authority-server-only mode: do not trigger local TOTP bootstrap.
end

