# frozen_string_literal: true

require 'pp'

namespace :instruments do
  desc 'Import instruments from DhanHQ CSV'
  task import: :environment do
    pp 'Starting instruments import...'
    start_time = Time.current

    begin
      result   = InstrumentsImporter.import_from_url
      duration = result[:duration] || (Time.current - start_time)
      pp "\nImport completed successfully in #{duration.round(2)} seconds!"
      pp "Total Instruments: #{result[:instrument_total]}"
      pp "Total Derivatives: #{result[:derivative_total]}"

      # Show some stats
      pp "\n--- Stats ---"
      pp "NSE Instruments: #{Instrument.nse.count}"
      pp "BSE Instruments: #{Instrument.bse.count}"
      pp "NSE Derivatives: #{Derivative.nse.count}"
      pp "BSE Derivatives: #{Derivative.bse.count}"
      pp "Options: #{Derivative.options.count}"
      pp "Futures: #{Derivative.futures.count}"
      pp 'Instruments: Instrument.count'
      pp 'Derivatives: Derivative.count'
      pp "TOTAL: #{Instrument.count + Derivative.count}"
    rescue StandardError => e
      pp "Import failed: #{e.message}"
      pp e.backtrace.join("\n")
    end
  end

  desc 'Clear all instruments and derivatives'
  task clear: :environment do
    pp 'Clearing all instruments and derivatives...'
    Derivative.delete_all
    Instrument.delete_all
    pp 'Cleared successfully!'
  end

  desc 'Reimport (clear and import)'
  task reimport: %i[clear import]

  desc 'Check instrument inventory freshness and counts'
  task status: :environment do
    last_import_raw = Setting.fetch('instruments.last_imported_at')

    unless last_import_raw
      pp 'No instrument import recorded yet.'
      exit 1
    end

    imported_at = Time.zone.parse(last_import_raw.to_s)
    age_seconds = Time.current - imported_at
    max_age     = InstrumentsImporter::CACHE_MAX_AGE

    pp "Last import at: #{imported_at}"
    pp "Age (seconds): #{age_seconds.round(2)}"
    pp "Import duration (sec): #{Setting.fetch('instruments.last_import_duration_sec', 'unknown')}"
    pp "Last instrument rows: #{Setting.fetch('instruments.last_instrument_rows', '0')}"
    pp "Last derivative rows: #{Setting.fetch('instruments.last_derivative_rows', '0')}"
    pp "Upserts (instruments): #{Setting.fetch('instruments.last_instrument_upserts', '0')}"
    pp "Upserts (derivatives): #{Setting.fetch('instruments.last_derivative_upserts', '0')}"
    pp "Total instruments: #{Setting.fetch('instruments.instrument_total', '0')}"
    pp "Total derivatives: #{Setting.fetch('instruments.derivative_total', '0')}"

    if age_seconds > max_age
      pp "Status: STALE (older than #{max_age.inspect})"
      exit 1
    end

    pp 'Status: OK'
  rescue ArgumentError => e
    pp "Failed to parse last import timestamp: #{e.message}"
    exit 1
  end
end

# Provide aliases for legacy singular namespace usage.
namespace :instrument do
  desc 'Alias for instruments:import'
  task import: 'instruments:import'

  desc 'Alias for instruments:clear'
  task clear: 'instruments:clear'

  desc 'Alias for instruments:reimport'
  task reimport: 'instruments:reimport'
end
