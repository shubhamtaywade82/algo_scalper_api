require 'vcr'
require 'webmock/rspec'
require 'dotenv/load'

VCR.configure do |c|
  c.cassette_library_dir = 'spec/vcr_cassettes'
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data('<DHAN_CLIENT_ID>') { ENV.fetch('DHAN_CLIENT_ID', 'test_client_id') }
  c.filter_sensitive_data('<DHAN_ACCESS_TOKEN>') { ENV.fetch('DHAN_ACCESS_TOKEN', 'test_access_token') }
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
