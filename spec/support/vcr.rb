# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter secrets from environment variables
  %w[CLIENT_ID DHANHQ_ACCESS_TOKEN RAILS_MASTER_KEY CLIENT_ID ACCESS_TOKEN].each do |key|
    val = ENV.fetch(key, nil)
    config.filter_sensitive_data("<#{key}>") { val } if val
  end

  # Filter sensitive headers - more comprehensive approach
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    # Check various header formats
    interaction.request.headers['Access-Token'] ||
      interaction.request.headers['access-token'] ||
      interaction.request.headers['ACCESS_TOKEN'] ||
      interaction.request.headers['access_token']
  end

  config.filter_sensitive_data('<CLIENT_ID>') do |interaction|
    # Check various header formats
    interaction.request.headers['Client-Id'] ||
      interaction.request.headers['client-id'] ||
      interaction.request.headers['CLIENT_ID'] ||
      interaction.request.headers['client_id']
  end

  config.filter_sensitive_data('<AUTHORIZATION>') do |interaction|
    interaction.request.headers['Authorization'] ||
      interaction.request.headers['authorization'] ||
      interaction.request.headers['AUTHORIZATION']
  end

  # Filter sensitive data from request body ONLY when present
  # Preserve the entire request body structure for proper VCR matching
  # This ensures request bodies without sensitive data are preserved exactly as-is
  config.before_record do |interaction|
    body = interaction.request.body

    # Only filter if body contains sensitive data, otherwise preserve as-is
    if body.is_a?(String)
      # Only filter if access_token or client_id are present in the body
      if body.include?('access_token') || body.include?('client_id')
        filtered_body = body.dup
        # Replace access_token value while preserving the JSON structure
        if body.include?('access_token')
          filtered_body = filtered_body.gsub(/"access_token"\s*:\s*"[^"]*"/,
                                             '"access_token":"<ACCESS_TOKEN>"')
        end
        if body.include?('client_id')
          filtered_body = filtered_body.gsub(/"client_id"\s*:\s*"[^"]*"/,
                                             '"client_id":"<CLIENT_ID>"')
        end
        interaction.request.body = filtered_body
      end
      # If no sensitive data, body is preserved as-is (no modification)
    elsif body.is_a?(Hash)
      # Filter hash body only if it contains sensitive keys
      if body.key?('access_token') || body.key?(:access_token) || body.key?('client_id') || body.key?(:client_id)
        filtered_body = body.dup
        if filtered_body['access_token'] || filtered_body[:access_token]
          filtered_body['access_token'] =
            '<ACCESS_TOKEN>'
        end
        filtered_body[:access_token] = '<ACCESS_TOKEN>' if filtered_body[:access_token]
        filtered_body['client_id'] = '<CLIENT_ID>' if filtered_body['client_id'] || filtered_body[:client_id]
        filtered_body[:client_id] = '<CLIENT_ID>' if filtered_body[:client_id]
        interaction.request.body = filtered_body.to_json if filtered_body.respond_to?(:to_json)
      end
      # If no sensitive data, body is preserved as-is (no modification)
    end
    # If body is nil or other type, leave it unchanged
  end

  # Allow localhost connections (Capybara or Rails server)
  config.ignore_localhost = true

  # Default to :once mode (use cassette if exists, record if missing)
  # Set ENV['VCR_MODE'] to 'all' to record all interactions, 'none' to disable recording
  config.default_cassette_options = {
    record: ENV.fetch('VCR_MODE', :once).to_sym,
    match_requests_on: %i[method uri body],
    allow_playback_repeats: true
  }

  # Add delay when recording to prevent rate limits
  config.before_record do |_interaction|
    # Small delay to prevent rapid API calls when recording
    sleep(ENV['VCR_RECORDING_DELAY'].to_f) if ENV['VCR_RECORDING_DELAY']
  end
end
