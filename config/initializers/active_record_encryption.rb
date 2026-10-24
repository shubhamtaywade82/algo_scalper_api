# frozen_string_literal: true

# Encrypts DhanAccessToken#token at rest (see app/models/dhan_access_token.rb).
# Keys generated once via `bin/rails db:encryption:init`, stored in ENV (matching this
# project's existing "secrets in .env, not credentials.yml.enc" convention — see
# .env.example). Losing these keys makes existing encrypted tokens unrecoverable.
Rails.application.configure do
  config.active_record.encryption.primary_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY', nil)
  config.active_record.encryption.deterministic_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY', nil)
  config.active_record.encryption.key_derivation_salt = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT', nil)
end
