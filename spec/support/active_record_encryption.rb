# frozen_string_literal: true

# DhanAccessToken encrypts its token column via Active Record encryption.
# Production keys come from Rails credentials, which do not exist in CI (no
# RAILS_MASTER_KEY) — without this support file every touch of the column
# raises ActiveRecord::Encryption::Errors::Configuration. These throwaway
# keys are fine for tests: the assertions that matter are round-trip
# correctness and ciphertext-at-rest, both key-agnostic.
return unless Rails.env.test?

ActiveRecord::Encryption.configure(
  primary_key: 'spec_active_record_encryption_primary_key',
  deterministic_key: 'spec_active_record_encryption_deterministic_key',
  key_derivation_salt: 'spec_active_record_encryption_key_derivation_salt'
)
