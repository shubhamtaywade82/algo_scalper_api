# frozen_string_literal: true

source 'https://rubygems.org'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'rails', '~> 8.1.3'
# Use postgresql as the database for Active Record
gem 'pg', '~> 1.6'
# SQLite for local-agent-stack shared memory & self-healing
gem 'sqlite3', '~> 2.0'
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
gem 'connection_pool', '~> 3.0'
gem 'json', '>= 2.19.2'
gem 'redis', '~> 6.0'
gem 'ruby-technical-analysis'
gem 'technical-analysis'

gem 'whenever', require: false

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

# DhanHQ Ruby client (v3 API wrapper and WebSocket feed)
gem 'DhanHQ', '~> 3.4'

# Telegram bot for notifications
gem 'telegram-bot-ruby', '~> 2.8'

gem 'aasm', '~> 5.5'
gem 'ollama-client', '~> 1.4'
gem 'prometheus_exporter', '~> 2.3'
gem 'ruby_llm', '~> 1.16'
gem 'ruby_llm-agents', '~> 3.15'

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem 'rack-cors'

# Per-IP throttling for expensive /api routes (disabled in test)
gem 'rack-attack', '~> 6.7'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem 'brakeman', require: false

  # Code quality and style enforcement
  gem 'rubocop', '~> 1.89', require: false
  gem 'rubocop-factory_bot', '~> 2.28', require: false
  gem 'rubocop-performance', '~> 1.27', require: false
  gem 'rubocop-rails', '~> 2.37', require: false
  gem 'rubocop-rspec', '~> 3.8', require: false
  gem 'rubocop-rspec_rails'

  # Static analysis / code health
  gem 'rails_best_practices', require: false
  gem 'rubycritic', require: false

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
  gem 'annotaterb'

  gem "debride"

  # N+1 query detection
  gem 'bullet'

  # Rails codebase indexing for AI coding assistant context
  gem 'woods'
end

gem "json_schemer", "~> 2.4"

gem "rswag", "~> 2.17", groups: %i[development test]
