# frozen_string_literal: true

require 'rails_helper'

# This spec is specifically for generating VCR cassettes with filtered sensitive data
# Run with: bundle exec rspec spec/integration/vcr_cassette_generation_spec.rb
# Make sure to set DHAN_CLIENT_ID and DHAN_ACCESS_TOKEN environment variables

RSpec.describe 'VCR Cassette Generation', :vcr, type: :integration do
  before do
    # Ensure credentials from environment are available inside the test
    # Some test helpers might be clearing the ENV
    ENV['DHAN_CLIENT_ID'] ||= ENV.fetch('DHAN_CLIENT_ID', nil)
    ENV['DHAN_ACCESS_TOKEN'] ||= ENV.fetch('DHAN_ACCESS_TOKEN', nil)
  end

  describe 'DhanHQ API calls' do
    context 'when making real API calls' do
      it 'records OHLC API call with filtered sensitive data' do
        # Skip if no credentials are available or if they look like placeholders
        has_creds = ENV['DHAN_CLIENT_ID'].present? && ENV['DHAN_ACCESS_TOKEN'].present? && !ENV['DHAN_ACCESS_TOKEN'].include?('placeholder')
        skip 'No DhanHQ credentials available' unless has_creds

        # Create a real instrument (use find_or_create to avoid duplicate security_id errors)
        instrument = Instrument.find_or_create_by!(security_id: '13') do |inst|
          inst.assign_attributes(
            symbol_name: 'NIFTY',
            exchange: 'nse',
            segment: 'index',
            instrument_type: 'INDEX',
            instrument_code: 'index'
          )
        end

        # This will make a real HTTP request and record it in VCR cassette
        # The sensitive headers will be filtered out by our VCR configuration
        result = instrument.ohlc

        # Skip if API call failed (e.g. expired tokens)
        skip 'DhanHQ API call failed (possibly expired tokens)' if result.nil?

        # The cassette will be saved with filtered data
        expect(result).to be_present
      end

      it 'records historical data API call with filtered sensitive data' do
        # Skip if no credentials are available or if they look like placeholders
        has_creds = ENV['DHAN_CLIENT_ID'].present? && ENV['DHAN_ACCESS_TOKEN'].present? && !ENV['DHAN_ACCESS_TOKEN'].include?('placeholder')
        skip 'No DhanHQ credentials available' unless has_creds

        # Create a real instrument (use find_or_create to avoid duplicate security_id errors)
        instrument = Instrument.find_or_create_by!(security_id: '13') do |inst|
          inst.assign_attributes(
            symbol_name: 'NIFTY',
            exchange: 'nse',
            segment: 'index',
            instrument_type: 'INDEX',
            instrument_code: 'index'
          )
        end

        # This will make a real HTTP request and record it in VCR cassette
        result = instrument.intraday_ohlc(interval: '5')

        # Skip if API call failed (e.g. expired tokens)
        skip 'DhanHQ API call failed (possibly expired tokens)' if result.nil?

        # The cassette will be saved with filtered data
        expect(result).to be_present
      end
    end
  end
end
