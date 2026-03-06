# frozen_string_literal: true

# Streams aggregate dashboard stats and position lifecycle events to subscribers.
# Broadcasts:
#   { type: "stats",              mode:, balance:, today:, indices:, circuit_breaker:, system:, timestamp: }
#   { type: "position_activated", position: { ... } }
#   { type: "position_exited",    position: { ... } }
class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'dashboard'
  end
end
