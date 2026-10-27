# frozen_string_literal: true

# Streams Market Brief frames (see Reports::MarketBrief::Broadcaster). Like
# DashboardChannel, it is not authenticated: the frames carry the same data the
# dashboard already receives over its own socket. The REST endpoints remain behind
# the dashboard token.
class MarketBriefChannel < ApplicationCable::Channel
  def subscribed
    stream_from Reports::MarketBrief::Broadcaster::CHANNEL
  end
end
