# frozen_string_literal: true

source 'https://rubygems.org'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'rails', '~> 8.0.2'
# Use postgresql as the database for Active Record
gem 'pg', '~> 1.1'
# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '>= 5.0'
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[windows jruby]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem 'solid_cable'
gem 'solid_cache'
gem 'solid_queue'

gem 'concurrent-ruby'
gem 'redis'
gem 'ruby-technical-analysis'
gem 'sidekiq'
gem 'technical-analysis'

# Bulk upserts for instruments/derivatives importer
gem 'activerecord-import'

# CSV will not be bundled with Ruby by default from 3.4+; we require it explicitly
gem 'csv', require: false

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem 'kamal', require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem 'thruster', require: false

# DhanHQ Ruby client (v2 API wrapper and WebSocket feed)
gem 'DhanHQ', git: 'https://github.com/shubhamtaywade82/dhanhq-client.git', branch: 'main'

# Telegram bot for notifications
gem 'telegram-bot-ruby', '~> 0.19'

# OpenAI API clients
# ruby-openai (alexrudall) - used in development/test
gem 'ruby-openai', '~> 8.0', group: %i[development test]

# openai-ruby (official) - used in production
gem 'openai', '~> 0.41', group: :production

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem 'rack-cors'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem 'brakeman', require: false

  # Code quality and style enforcement
  gem 'rubocop', '~> 1.71', require: false
  gem 'rubocop-factory_bot', '~> 2.25', require: false
  gem 'rubocop-performance', '~> 1.21', require: false
  gem 'rubocop-rails', '~> 2.23', require: false
  gem 'rubocop-rspec', '~> 3.0', require: false
  gem 'rubocop-rspec_rails'

  # Load .env files in development/test before initializers
  gem 'dotenv-rails'

  # Testing stack
  gem 'database_cleaner-active_record'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rspec-rails'
  gem 'shoulda-matchers'
  gem 'simplecov', require: false
  gem 'vcr', require: false
  gem 'webmock', require: false

  # Annotate models, routes, etc.
  gem 'annotate'
end
