# frozen_string_literal: true

# Streams strategy status transitions and periodic heartbeats.
#
# Subscribe: client-side `StrategyStatusChannel`
# Broadcast: `ActionCable.server.broadcast("strategy_status", {slug:, status:, ...})`
class StrategyStatusChannel < ApplicationCable::Channel
  def subscribed
    stream_from "strategy_status"
  end
end
