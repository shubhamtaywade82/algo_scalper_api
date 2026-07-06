# frozen_string_literal: true

# Streams real-time alert pushes to the dashboard.
# Broadcasts:
#   { alert: { id:, type:, severity:, message:, read:, created_at: } }
class AlertsChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'alerts'
  end
end
