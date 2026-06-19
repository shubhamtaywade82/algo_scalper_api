# frozen_string_literal: true

# Canonical runtime config is AlgoConfig.fetch (DB document via AlgoConfig::DocumentStore).
# config/algo.yml is seed-only; do not read it at boot for trading logic.
Rails.application.configure do
  config.x.algo = ActiveSupport::InheritableOptions.new({})
end

# Subscribe to Redis invalidation so web/trading/jobs pick up DB config changes immediately.
Rails.application.config.after_initialize do
  AlgoConfig::CacheBroadcaster.start_subscriber!
end
