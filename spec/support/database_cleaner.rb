# frozen_string_literal: true

require 'database_cleaner-active_record'

RSpec.configure do |config|
  config.before(:suite) do
    # Step 1: Set cleaning strategy
    DatabaseCleaner.strategy = :transaction

    # Step 2: Truncate all tables to start fresh
    DatabaseCleaner.clean_with(:truncation)

    # Step 3: Import instruments and derivatives after truncation
    # This populates the database with real data (NIFTY-13, BANKNIFTY-25, SENSEX-51, etc.)
    # and all their derivatives before tests run
    if ENV['IMPORT_INSTRUMENTS_FOR_TESTS'] == 'true' || ENV['AUTO_IMPORT_INSTRUMENTS'] == 'true'
      Rails.logger.info '[DatabaseCleaner] Importing instruments and derivatives after truncation...'

      # Use filtered CSV if available and FILTERED_CSV=true, otherwise use full CSV
      csv_path = if ENV['FILTERED_CSV'] == 'true'
                   filtered_path = Rails.root.join('tmp/dhan_scrip_master_filtered.csv')
                   filtered_path.exist? ? filtered_path : Rails.root.join('tmp/dhan_scrip_master.csv')
                 else
                   Rails.root.join('tmp/dhan_scrip_master.csv')
                 end

      if csv_path.exist?
        csv_type = csv_path.basename.to_s.include?('filtered') ? 'filtered' : 'full'
        Rails.logger.info "[DatabaseCleaner] Using #{csv_type} CSV: #{csv_path}"
        csv_content = csv_path.read

        begin
          result = InstrumentsImporter.import_from_csv(csv_content)
          Rails.logger.info "[DatabaseCleaner] Imported #{result[:instrument_upserts]} instruments, #{result[:derivative_upserts]} derivatives"

          # Verify key instruments are present
          nifty = Instrument.segment_index.find_by(security_id: '13', symbol_name: 'NIFTY')
          banknifty = Instrument.segment_index.find_by(security_id: '25', symbol_name: 'BANKNIFTY')
          sensex = Instrument.segment_index.find_by(security_id: '51', symbol_name: 'SENSEX')

          Rails.logger.info "[DatabaseCleaner] NIFTY (13): #{nifty ? '✓' : '✗'}, BANKNIFTY (25): #{banknifty ? '✓' : '✗'}, SENSEX (51): #{sensex ? '✓' : '✗'}"
        rescue StandardError => e
          Rails.logger.error "[DatabaseCleaner] Failed to import instruments: #{e.class} - #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
        end
      else
        Rails.logger.warn "[DatabaseCleaner] CSV cache not found at #{csv_path}"
        Rails.logger.warn '[DatabaseCleaner] Run `RAILS_ENV=test bin/rails test:instruments:import` ' \
                          'to download and cache CSV'
        Rails.logger.warn '[DatabaseCleaner] Tests will use factory-created instruments as fallback'
      end
    else
      Rails.logger.info '[DatabaseCleaner] Instrument import skipped ' \
                        '(set IMPORT_INSTRUMENTS_FOR_TESTS=true or AUTO_IMPORT_INSTRUMENTS=true to enable)'
    end
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
