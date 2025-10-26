# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
ENV['DHANHQ_ENABLED'] ||= 'false'
ENV['DHANHQ_WS_ENABLED'] ||= 'false'
ENV['DHANHQ_ORDER_WS_ENABLED'] ||= 'false'
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

  config.include FactoryBot::Syntax::Methods
end
