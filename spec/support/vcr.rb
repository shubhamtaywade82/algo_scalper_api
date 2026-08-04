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
    TRADER_API_BASE_URL
  ]

  sensitive_env_vars.each do |key|
    val = ENV.fetch(key, nil)
    config.filter_sensitive_data("<#{key}>") { val } if val && !val.empty?
  end

  # Mask the Trader API base URL specifically if it's set
  if ENV['TRADER_API_BASE_URL'].present?
    config.filter_sensitive_data('<TRADER_API_BASE_URL>') { ENV['TRADER_API_BASE_URL'] }
  end

  # Filter SENSITIVE_SERVICE_URL (onrender.com)
  config.filter_sensitive_data('<SENSITIVE_SERVICE_URL>') do
    'algo-trading-api.onrender.com'
  end

  # Filter sensitive headers - more comprehensive approach
  # We use blocks that return the value to be replaced.
  # VCR will replace all occurrences of these values in the cassette.
  
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    headers = interaction.request.headers
    vals = Array(headers['Access-Token'] || headers['access-token'] || headers['ACCESS_TOKEN'])
    # We want to filter ANY value that looks like a token
    vals.find { |v| v.to_s.length > 10 && v.to_s != '<ACCESS_TOKEN>' }
  end

  config.filter_sensitive_data('<CLIENT_ID>') do |interaction|
    headers = interaction.request.headers
    vals = Array(headers['Client-Id'] || headers['client-id'] || headers['CLIENT_ID'])
    vals.find { |v| v.to_s.length > 3 && v.to_s != '<CLIENT_ID>' }
  end

  config.filter_sensitive_data('<AUTHORIZATION>') do |interaction|
    headers = interaction.request.headers
    vals = Array(headers['Authorization'] || headers['authorization'] || headers['AUTHORIZATION'])
    vals.find { |v| v.to_s.length > 10 && v.to_s != '<AUTHORIZATION>' }
  end

  # Comprehensive sensitive data filtering for BOTH request and response bodies
  # This acts as an "automatic masking facility" that doesn't rely solely on ENV variables
  config.before_record do |interaction|
    [interaction.request, interaction.response].each do |obj|
      next unless obj.body.is_a?(String) && !obj.body.empty?
      
      begin
        # Perform replacements on a copy of the body
        filtered_body = obj.body.dup
        
        # 1. Targeted JSON key scrubbing
        if filtered_body.start_with?('{', '[')
          # Replace access_token value
          filtered_body.gsub!(/"access_token"\s*:\s*"[^"]*"/, '"access_token":"<ACCESS_TOKEN>"')
          
          # Replace client_id/dhanClientId values
          filtered_body.gsub!(/"client_id"\s*:\s*"[^"]*"/, '"client_id":"<CLIENT_ID>"')
          filtered_body.gsub!(/"dhanClientId"\s*:\s*"[^"]*"/, '"dhanClientId":"<CLIENT_ID>"')
          
          # Replace Authorization header in JSON if present
          filtered_body.gsub!(/"Authorization"\s*:\s*"Bearer\s+[^"]*"/i, '"Authorization":"Bearer <AUTHORIZATION>"')
        end
        
        # 2. Pattern-based scrubbing (Automatic Facility)
        # Scrub JWT tokens (base64-encoded JSON header starting with eyJ0eXAi)
        # Matches typical JWT structure: head.payload.signature
        jwt_pattern = /eyJ0eXAi[a-zA-Z0-9\-\._~+\/]+=*/
        filtered_body.gsub!(jwt_pattern, '<ACCESS_TOKEN>')
        
        # Scrub Bearer tokens in any string (not just JSON keys)
        # Standard Bearer tokens are alphanumeric with some symbols
        bearer_pattern = /Bearer\s+[a-zA-Z0-9\-\._~+\/]+=*/
        filtered_body.gsub!(bearer_pattern, 'Bearer <AUTHORIZATION>')
        
        # Scrub potential Render/Heroku app URLs if they look sensitive
        # Matches things like https://my-app.onrender.com or https://my-app.herokuapp.com
        url_pattern = /https:\/\/[a-zA-Z0-9\-]+\.(onrender\.com|herokuapp\.com)/
        filtered_body.gsub!(url_pattern, '<SENSITIVE_SERVICE_URL>')
        
        obj.body = filtered_body
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
