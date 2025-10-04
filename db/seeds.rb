# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Seed default index watchlist: NIFTY, BANKNIFTY, SENSEX
# Dhan index segment is IDX_I; common security_ids:
#   NIFTY index value: 13
#   BANKNIFTY index value: 25
#   SENSEX index value: 1 (placeholder; update if mapping differs)

# Ensure instrument import is present and recent before adding watchlist
last_import_raw = Setting.fetch('instruments.last_imported_at')
if last_import_raw.blank?
  puts "Skipping watchlist seed: no instrument import recorded. Run `bin/rails instruments:import` first."
else
  imported_at = Time.zone.parse(last_import_raw.to_s) rescue nil
  if imported_at.nil?
    puts "Skipping watchlist seed: could not parse last import timestamp (#{last_import_raw.inspect})."
  else
    max_age = InstrumentsImporter::CACHE_MAX_AGE
    age = Time.current - imported_at
    if age > max_age
      puts "Skipping watchlist seed: import is stale (age=#{age.round(1)}s > #{max_age.inspect}). Run `bin/rails instruments:reimport`."
    else
      items = [
        { segment: "IDX_I", security_id: "13",  kind: :index_value, label: "NIFTY" },
        { segment: "IDX_I", security_id: "25",  kind: :index_value, label: "BANKNIFTY" },
        { segment: "IDX_I", security_id: "1",   kind: :index_value, label: "SENSEX" }
      ]

      items.each do |attrs|
        WatchlistItem.find_or_create_by!(segment: attrs[:segment], security_id: attrs[:security_id]) do |rec|
          rec.kind  = attrs[:kind]
          rec.label = attrs[:label]
          rec.active = true
        end
      end

      puts "Seeded #{items.size} index watchlist items"
    end
  end
end
