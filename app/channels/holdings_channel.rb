# frozen_string_literal: true

# Streams holdings refresh signals — broadcasts when positions open/close
# so the dashboard refetches broker holdings data.
# Broadcasts:
#   { type: "holdings_changed", timestamp: }
class HoldingsChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'holdings'
  end
end
