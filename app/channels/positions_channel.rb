# frozen_string_literal: true

# Streams per-position PnL updates (sub-second) to subscribers.
# Broadcasts:
#   { type: "pnl_update", id:, ltp:, pnl:, pnl_pct:, hwm_pnl: }
class PositionsChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'positions'
  end
end
