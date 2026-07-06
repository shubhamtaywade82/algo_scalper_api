# frozen_string_literal: true

# Streams funds refresh signals — broadcasts when positions open/close
# or when funds are added/withdrawn, so the dashboard refetches fund data.
# Broadcasts:
#   { type: "funds_changed", timestamp: }
class FundsChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'funds'
  end
end
