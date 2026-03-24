# frozen_string_literal: true

# Boot-time token prefetch for the trading daemon.
# Only runs when ENABLE_TRADING_SERVICES=true (trading process, not web).
#
# Calls TokenManager.refresh! which uses the DHAN_AUTH_MODE strategy:
#   totp       - generate TOTP and login directly with Dhan (default)
#   manual     - read DHAN_ACCESS_TOKEN from ENV
#   renew      - renew an existing DB token
#   authority  - fetch from external authority server
Rails.application.config.after_initialize do
  next if Rails.const_defined?(:Console)
  next if Rails.env.test?
  next if ENV["DISABLE_TRADING_SERVICES"] == "1"
  next unless ENV["ENABLE_TRADING_SERVICES"] == "true"

  mode = ENV.fetch("DHAN_AUTH_MODE", "totp")

  begin
    token = Dhan::TokenManager.refresh!(force: false)
    if token.present?
      Rails.logger.info("[SCALPER] Dhan token prefetched via #{mode} strategy")
    else
      Rails.logger.error(
        "[SCALPER] Dhan token prefetch returned nil (mode=#{mode}). " \
        "Check DHAN_AUTH_MODE and required ENV vars for the chosen strategy."
      )
    end
  rescue StandardError => e
    Rails.logger.error(
      "[SCALPER] Dhan token prefetch failed (mode=#{mode}): #{e.message}. " \
      "Verify DHAN_AUTH_MODE and the required ENV vars are set correctly."
    )
  end
end
