# frozen_string_literal: true

class GetClosedPositionsTool < ApplicationMCPTool
  INDICES = %w[NIFTY BANKNIFTY SENSEX].freeze

  tool_name 'get_closed_positions'
  description 'Recently closed positions for the active trading mode with realized P&L, newest exit first. Read-only.'

  property :index, type: 'string', description: 'Filter by index; omit for all', enum: INDICES
  property :limit, type: 'integer', description: 'Max rows (default 20, max 100)'

  def perform
    snapshot = market_snapshot
    scope = snapshot['mode'] == 'paper' ? PositionTracker.paper : PositionTracker.live
    scope = scope.where(status: :exited)
    scope = scope.where(index_key: index) if index.present?
    trackers = scope.order(exited_at: :desc).limit((limit || 20).to_i.clamp(1, 100))

    rows = trackers.map { |t| Positions::Serializer.closed(t) }
    render_json(generated_at: snapshot['generated_at'], count: rows.size, closed_positions: rows)
  end
end
