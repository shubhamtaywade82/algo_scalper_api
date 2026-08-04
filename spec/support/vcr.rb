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

  # Filter SENSITIVE_SERVICE_URL (onrender.com)
  config.filter_sensitive_data('<SENSITIVE_SERVICE_URL>') do
    'algo-trading-api.onrender.com'
  end

  # Filter sensitive headers - more comprehensive approach
  # We use blocks that return the value to be replaced.
  # VCR will replace all occurrences of these values in the cassette.
  
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    # Check various header formats for access-token
    (interaction.request.headers['Access-Token'] ||
      interaction.request.headers['access-token'] ||
      interaction.request.headers['ACCESS_TOKEN'])&.first
  end

  # Masking Bearer tokens (even if not JWT)
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    auth_header = (interaction.request.headers['Authorization'] || interaction.request.headers['authorization'])&.first
    if auth_header && (match = auth_header.match(/^Bearer\s+(.+)$/))
      match[1]
    end
  end

  # Masking JWT tokens (starting with eyJ) in headers and bodies
  config.filter_sensitive_data('<ACCESS_TOKEN>') do |interaction|
    jwt_regex = /eyJ[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+/
    
    # Check Authorization header for JWT
    auth_header = (interaction.request.headers['Authorization'] || interaction.request.headers['authorization'])&.first
    if auth_header && (match = auth_header.match(jwt_regex))
      match[0]
    # Check body for any JWT
    elsif (match = interaction.request.body&.match(jwt_regex))
      match[0]
    elsif (match = interaction.response.body&.match(jwt_regex))
      match[0]
    end
  end

  config.filter_sensitive_data('<CLIENT_ID>') do |interaction|
    # Check various header formats for client-id
    (interaction.request.headers['Client-Id'] ||
      interaction.request.headers['client-id'] ||
      interaction.request.headers['CLIENT_ID'])&.first
  end

  # Filter sensitive data from request body ONLY when present
  # Preserve the entire request body structure for proper VCR matching
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
    elsif body.is_a?(Hash)
      # Filter hash body only if it contains sensitive keys
      if body.key?('access_token') || body.key?(:access_token) || body.key?('client_id') || body.key?(:client_id)
        filtered_body = body.dup
        if filtered_body['access_token'] || filtered_body[:access_token]
          filtered_body['access_token'] = '<ACCESS_TOKEN>'
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
