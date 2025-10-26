# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter secrets from environment variables
  %w[DHANHQ_CLIENT_ID DHANHQ_ACCESS_TOKEN RAILS_MASTER_KEY CLIENT_ID ACCESS_TOKEN].each do |key|
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

  # Filter sensitive data from request body
  config.filter_sensitive_data('<REQUEST_BODY>') do |interaction|
    body = interaction.request.body
    if body&.include?('access_token')
      body.gsub(/"access_token":"[^"]*"/, '"access_token":"<ACCESS_TOKEN>"')
          .gsub(/"client_id":"[^"]*"/, '"client_id":"<CLIENT_ID>"')
    else
      body
    end
  end

  # Allow localhost connections (Capybara or Rails server)
  config.ignore_localhost = true
end
