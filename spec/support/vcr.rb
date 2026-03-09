# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter secrets from environment variables
  sensitive_env_vars = %w[
    CLIENT_ID
    DHAN_CLIENT_ID
    ACCESS_TOKEN
    DHAN_ACCESS_TOKEN
    DHAN_TOKEN_ACCESS_TOKEN
    RAILS_MASTER_KEY
    DHANHQ_PARTNER_ID
    DHANHQ_PARTNER_SECRET
    TELEGRAM_BOT_TOKEN
    TELEGRAM_CHAT_ID
    ALGO_SCALPER_API_DATABASE_PASSWORD
    KAMAL_REGISTRY_PASSWORD
  ]

  sensitive_env_vars.each do |key|
    val = ENV.fetch(key, nil)
    config.filter_sensitive_data("<#{key}>") { val } if val && !val.empty?
  end

  # Filter sensitive headers - more comprehensive approach
  # We use blocks that return the value to be replaced.
  # VCR will replace all occurrences of these values in the cassette.
  
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    headers = interaction.request.headers
    val = headers['Access-Token'] || headers['access-token'] || headers['ACCESS_TOKEN']
    val = val.first if val.is_a?(Array)
    val if val && val != '<ACCESS_TOKEN>' && val.length > 10
  end

  config.filter_sensitive_data('<CLIENT_ID>') do |interaction|
    headers = interaction.request.headers
    val = headers['Client-Id'] || headers['client-id'] || headers['CLIENT_ID']
    val = val.first if val.is_a?(Array)
    val if val && val != '<CLIENT_ID>' && val.length > 3
  end

  config.filter_sensitive_data('<AUTHORIZATION>') do |interaction|
    headers = interaction.request.headers
    val = headers['Authorization'] || headers['authorization'] || headers['AUTHORIZATION']
    val = val.first if val.is_a?(Array)
    # If it's a Bearer token, we might want to just filter the token part, 
    # but filter_sensitive_data replaces the whole string. 
    # Returning the whole "Bearer ..." string will replace it with <AUTHORIZATION>.
    val if val && val != '<AUTHORIZATION>' && val.length > 10
  end

  # Comprehensive sensitive data filtering for BOTH request and response bodies
  config.before_record do |interaction|
    [interaction.request, interaction.response].each do |obj|
      next unless obj.body.is_a?(String) && !obj.body.empty?
      
      begin
        # If it looks like JSON, we do targeted replacement
        if obj.body.start_with?('{', '[')
          filtered_body = obj.body.dup
          
          # Replace access_token value
          filtered_body.gsub!(/"access_token"\s*:\s*"[^"]*"/, '"access_token":"<ACCESS_TOKEN>"')
          
          # Replace client_id/dhanClientId values
          filtered_body.gsub!(/"client_id"\s*:\s*"[^"]*"/, '"client_id":"<CLIENT_ID>"')
          filtered_body.gsub!(/"dhanClientId"\s*:\s*"[^"]*"/, '"dhanClientId":"<CLIENT_ID>"')
          
          # Replace potential Bearer tokens in strings
          filtered_body.gsub!(/Bearer\s+[a-zA-Z0-9\-\._~+\/]+=*/, 'Bearer <AUTHORIZATION>')
          
          obj.body = filtered_body
        end
      rescue StandardError => e
        Rails.logger.error "[VCR] Error filtering body: #{e.message}"
      end
    end
  end

  # Allow localhost connections (Capybara or Rails server)
  config.ignore_localhost = true

  # Default to :once mode (use cassette if exists, record if missing)
  config.default_cassette_options = {
    record: ENV.fetch('VCR_MODE', :once).to_sym,
    match_requests_on: %i[method uri body],
    allow_playback_repeats: true
  }

  # Add delay when recording to prevent rate limits
  config.before_record do |_interaction|
    sleep(ENV['VCR_RECORDING_DELAY'].to_f) if ENV['VCR_RECORDING_DELAY']
  end
end
