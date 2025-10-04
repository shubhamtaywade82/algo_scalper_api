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
      # Resolve by exchange + INDEX segment + symbol name (more robust than hardcoding IDs)
      queries = [
        { label: "NIFTY",      exchange: "NSE", symbol_like: "%NIFTY%" },
        { label: "BANKNIFTY",  exchange: "NSE", symbol_like: "%BANKNIFTY%" },
        { label: "SENSEX",     exchange: "BSE", symbol_like: "%SENSEX%" }
      ]

      created = 0
      queries.each do |q|
        instrument = Instrument
                      .where(exchange: q[:exchange])
                      .where(segment: "I")
                      .where("(instrument_code = ? OR instrument_type = ?)", "INDEX", "INDEX")
                      .where("symbol_name ILIKE ?", q[:symbol_like])
                      .order(Arel.sql("LENGTH(symbol_name) ASC"))
                      .first

        unless instrument
          puts "Skipping #{q[:label]}: Instrument not found (exchange=#{q[:exchange]} segment=INDEX symbol_name ILIKE #{q[:symbol_like]})"
          next
        end

        seg_code = instrument.exchange_segment
        wl = WatchlistItem.find_or_initialize_by(segment: seg_code, security_id: instrument.security_id)
        wl.label = q[:label]
        wl.kind  = :index_value
        wl.active = true
        wl.watchable = instrument
        wl.save!
        created += 1 if wl.persisted?
      end

      puts "Seeded/Ensured #{created} index watchlist items with associations"
    end
  end
end
