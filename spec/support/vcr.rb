# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter secrets
  %w[DHANHQ_CLIENT_ID DHANHQ_ACCESS_TOKEN RAILS_MASTER_KEY].each do |key|
    val = ENV[key]
    config.filter_sensitive_data("<#{key}>") { val } if val
  end

  # Allow localhost connections (Capybara or Rails server)
  config.ignore_localhost = true
end
