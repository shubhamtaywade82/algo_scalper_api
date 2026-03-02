# frozen_string_literal: true

# Boot-time safety: ensure a valid Dhan token exists for long-running services.
# Uses ENV-based secrets (via dotenv in dev/test) and persists token in DB.

Rails.application.config.after_initialize do
  next if Rails.const_defined?(:Console)
  next if Rails.env.test?
  next if ENV['DISABLE_TRADING_SERVICES'] == '1'

  # Only bootstrap if TOTP refresh is configured
  client_id_present = ENV['CLIENT_ID'].present? || ENV['DHAN_CLIENT_ID'].present?
  required = %w[DHAN_PIN DHAN_TOTP_SECRET]
  next unless client_id_present && required.all? { |key| ENV[key].present? }

  Dhan::TokenManager.current_token! if defined?(Dhan::TokenManager)
end

