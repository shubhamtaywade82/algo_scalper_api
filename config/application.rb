require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
# require "active_storage/engine"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie" if Rails.env.development?
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AlgoScalperApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    #
    # `research` holds standalone research scripts (top-level side-effecting code,
    # no wrapping module) meant to be run directly via `ruby lib/research/*.rb` —
    # they are not Zeitwerk-conformant and crash eager loading (and thus production
    # boot) if autoloaded.
    # `backtest_engine` is a self-contained vendored gem (own Gemfile/gemspec/spec
    # suite) and must not be autoloaded by the parent app's Zeitwerk loader.
    # `calibration` is orphaned/incomplete code that require_relatives files
    # (indicators/primitives, indicators/super_trend2, indicators/dmi) that don't
    # exist in the repo, breaking eager loading.
    config.autoload_lib(ignore: %w[assets tasks research backtest_engine calibration])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Asia/Kolkata"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.active_job.queue_adapter = :solid_queue
  end
end
