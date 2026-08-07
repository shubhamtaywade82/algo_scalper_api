# frozen_string_literal: true

# DhanAccessToken#token gained `encrypts :token` (app/models/dhan_access_token.rb).
# Rows written before that change are still plaintext; reading `#token` on them now
# raises ActiveRecord::Encryption::Errors::Decryption. support_unencrypted_data lets a
# read fall back to the raw column value instead of raising, so this re-saves every
# existing row once to bring it under encryption without any downtime.
class ReencryptExistingDhanAccessTokens < ActiveRecord::Migration[8.1]
  def up
    previous = ActiveRecord::Encryption.config.support_unencrypted_data
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    DhanAccessToken.find_each do |record|
      record.update_column(:token, record.token) # rubocop:disable Rails/SkipsModelValidations
    end
  ensure
    ActiveRecord::Encryption.config.support_unencrypted_data = previous
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
