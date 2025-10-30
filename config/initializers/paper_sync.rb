# frozen_string_literal: true

# Sync paper positions from PositionTracker (PostgreSQL) to Redis on startup
# This ensures positions survive server restarts even if Redis is cleared
Rails.application.config.to_prepare do
  # Legacy PositionSync is not required with daily-namespaced Paper::GatewayV2
  # Intentionally no-op in paper mode to avoid conflicting state.
  next unless ExecutionMode.paper?
end


