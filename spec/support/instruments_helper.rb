# frozen_string_literal: true

# Helper to import Instruments and Derivatives in test environment
# This ensures tests use real security IDs and instrument data
module InstrumentsHelper
  def self.ensure_instruments_imported!
    return true if instruments_already_imported?

    Rails.logger.info '[InstrumentsHelper] Importing instruments and derivatives for test environment...'

    csv_path = Rails.root.join('tmp/dhan_scrip_master.csv')
    if csv_path.exist?
      Rails.logger.info "[InstrumentsHelper] Using cached CSV: #{csv_path}"
      csv_content = csv_path.read
    else
      Rails.logger.warn "[InstrumentsHelper] CSV cache not found at #{csv_path}"
      Rails.logger.warn '[InstrumentsHelper] Run `RAILS_ENV=test bin/rails test:instruments:import` ' \
                        'to download and import'
      return false
    end

    result = InstrumentsImporter.import_from_csv(csv_content)
    Rails.logger.info "[InstrumentsHelper] Imported #{result[:instrument_upserts]} instruments, #{result[:derivative_upserts]} derivatives"

    true
  rescue StandardError => e
    Rails.logger.error "[InstrumentsHelper] Failed to import instruments: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    false
  end

  def self.instruments_already_imported?
    # Check if we have at least the basic index instruments
    Instrument.segment_index.where(symbol_name: %w[NIFTY BANKNIFTY]).count >= 2
  end

  def self.find_real_instrument(symbol_name:, exchange: 'NSE', segment: 'index')
    Instrument.where(symbol_name: symbol_name, exchange: exchange, segment: segment).first
  end

  def self.find_real_derivative(symbol_name:, exchange: 'NSE', segment: 'derivatives')
    Derivative.where(symbol_name: symbol_name, exchange: exchange, segment: segment).first
  end
end

# NOTE: Instrument import is now handled by database_cleaner.rb after truncation
# This ensures instruments are imported in the correct order:
# 1. Truncate database
# 2. Import instruments and derivatives
# 3. Run tests
#
# To enable auto-import, set: IMPORT_INSTRUMENTS_FOR_TESTS=true or AUTO_IMPORT_INSTRUMENTS=true
