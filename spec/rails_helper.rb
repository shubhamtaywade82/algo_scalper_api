# frozen_string_literal: true

require 'timeout'

# SimpleCov must be required before any application code (skip with COVERAGE=false for faster runs)
if ENV['COVERAGE'] != 'false'
  require 'simplecov'
  SimpleCov.start 'rails' do
    minimum_coverage 0
    add_filter '/spec/'
    add_filter '/config/'
    add_filter '/vendor/'
    add_filter '/db/'
    add_filter '/lib/tasks/'
    add_filter '/tmp/'
    add_group 'Models', 'app/models'
    add_group 'Controllers', 'app/controllers'
    add_group 'Services', 'app/services'
    add_group 'Jobs', 'app/jobs'
    add_group 'Mailers', 'app/mailers'
    add_group 'Helpers', 'app/helpers'
    add_group 'Libraries', 'lib/'
    coverage_dir 'coverage'
  end
end

ENV['RAILS_ENV'] ||= 'test'
ENV['DHANHQ_ENABLED'] ||= 'false'
# Default specs to paper execution; examples that need live gateway set LIVE_TRADING explicitly.
ENV['LIVE_TRADING'] ||= 'false'
require File.expand_path('../config/environment', __dir__)
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'

# Maintain test schema
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

# Require support files
Rails.root.glob('spec/support/**/*.rb').each { |f| require f }

RSpec.configure do |config|
  # These settings depend on rspec-rails features; guard in case APIs change
  config.fixture_path = Rails.root.join('spec/fixtures').to_s if config.respond_to?(:fixture_path=)
  config.use_transactional_fixtures = false if config.respond_to?(:use_transactional_fixtures=)
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.example_status_persistence_file_path = 'spec/failed_examples.txt'

  config.include FactoryBot::Syntax::Methods

  # Add delay between tests that use VCR to prevent rate limits
  # This is especially important when regenerating cassettes
  # RSpec runs sequentially by default (no parallel execution unless using parallel_tests gem)
  config.after(:each, :vcr) do
    # Only add delay when recording new cassettes (not during playback)
    if VCR.current_cassette&.recording?
      delay = ENV.fetch('VCR_DELAY_BETWEEN_TESTS', '0.5').to_f
      sleep(delay) if delay.positive?
    end
  end

  # Optional: Add small delay between all tests if TEST_DELAY is set
  # Usage: TEST_DELAY=0.1 bundle exec rspec
  if ENV['TEST_DELAY']
    config.after(:each) do
      sleep(ENV['TEST_DELAY'].to_f)
    end
  end

  # Optional: Per-example timeout to surface hanging specs (e.g. RSPEC_TIMEOUT=60)
  if (timeout_sec = ENV['RSPEC_TIMEOUT']&.to_i) && timeout_sec.positive?
    config.around(:each) do |example|
      Timeout.timeout(timeout_sec) { example.run }
    end
  end
end
