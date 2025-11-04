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

  desc 'Reimport instruments and derivatives (upserts - adds new, updates existing, preserves positions)'
  task reimport: :environment do
    pp 'Starting instruments reimport (upsert mode)...'
    pp 'Note: Import uses upsert logic - will add new contracts and update existing ones.'
    pp 'Existing instruments/derivatives will NOT be deleted, so positions remain safe.'
    pp ''
    Rake::Task['instruments:import'].invoke
  end

  desc 'Clear all instruments and derivatives (DANGER: Will fail if active positions exist)'
  desc 'Only use this if you need to completely reset the database. Normal imports use upsert and do not require clearing.'
  task :clear, [:force] => :environment do |_t, args|
    pp '⚠️  WARNING: This will delete ALL instruments and derivatives!'
    pp '⚠️  This is usually NOT needed since imports use upsert (add/update only).'
    pp ''

    # Check for active position trackers that reference instruments
    active_trackers = PositionTracker.where(status: PositionTracker::STATUSES[:active])
    if active_trackers.any?
      pp "ERROR: Found #{active_trackers.count} active position tracker(s) that reference instruments."
      pp 'Active trackers:'
      active_trackers.limit(10).each do |tracker|
        pp "  - Order: #{tracker.order_no}, Instrument ID: #{tracker.instrument_id}, Status: #{tracker.status}, Symbol: #{tracker.symbol}"
      end

      if args[:force] == 'true'
        pp ''
        pp "FORCE mode enabled: Marking active position trackers as 'closed'..."
        active_trackers.update_all(
          status: PositionTracker::STATUSES[:closed],
          updated_at: Time.current
        )
        pp "Marked #{active_trackers.count} active tracker(s) as closed."
      else
        pp ''
        pp 'To force clear (will mark active positions as closed), run:'
        pp '  bin/rails instruments:clear[true]'
        pp 'Or manually close/exit positions first.'
        pp ''
        pp '💡 TIP: You probably don\'t need to clear - just run `bin/rails instruments:reimport`'
        pp '    which uses upsert and safely adds/updates without deleting.'
        raise 'Cannot clear instruments while active position trackers exist'
      end
    end

    # Delete inactive/closed trackers that reference instruments (to avoid FK constraint issues)
    inactive_trackers = PositionTracker.where.not(status: PositionTracker::STATUSES[:active])
    if inactive_trackers.any?
      pp "Found #{inactive_trackers.count} inactive/closed position tracker(s)."
      if args[:force] == 'true'
        pp 'FORCE mode: Deleting inactive trackers to avoid FK constraints...'
        inactive_trackers.delete_all
        pp "Deleted #{inactive_trackers.count} inactive tracker(s)."
      else
        pp 'These will cause FK constraint errors. To delete them, use force mode:'
        pp '  bin/rails instruments:clear[true]'
        pp '⚠️  Or they will prevent instrument deletion.'
      end
    end

    pp ''
    pp 'Proceeding with deletion of all instruments and derivatives...'
    # Now safe to delete derivatives and instruments
    Derivative.delete_all
    Instrument.delete_all
    pp '✅ Cleared successfully!'
  end

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
