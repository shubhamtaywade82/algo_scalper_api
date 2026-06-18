# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
if ActiveRecord::Base.connection.data_source_exists?('market_holidays')
  load Rails.root.join('db/seeds/market_holidays.rb')
end

# Seed default index watchlist: NIFTY, BANKNIFTY, SENSEX
# Dhan index segment is IDX_I; common security_ids:
#   NIFTY index value: 13
#   BANKNIFTY index value: 25
#   SENSEX index value: 51

# Ensure instrument import is present and recent before adding watchlist
last_import_raw = Setting.fetch('instruments.last_imported_at')
if last_import_raw.blank?
  Rails.logger.debug "Skipping watchlist seed: no instrument import recorded. Run `bin/rails instruments:import` first."
else
  imported_at = begin
    Time.zone.parse(last_import_raw.to_s)
  rescue StandardError
    nil
  end
  if imported_at.nil?
    Rails.logger.debug "Skipping watchlist seed: could not parse last import timestamp (#{last_import_raw.inspect})."
  else
    max_age = InstrumentsImporter::CACHE_MAX_AGE
    age = Time.current - imported_at
    if age > max_age
      Rails.logger.debug "Skipping watchlist seed: import is stale (age=#{age.round(1)}s > #{max_age.inspect}). Run `bin/rails instruments:reimport`."
    else
      DbSeeds.seed_default_index_watchlist
    end
  end
end
