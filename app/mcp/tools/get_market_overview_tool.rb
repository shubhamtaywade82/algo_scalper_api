# frozen_string_literal: true

class GetMarketOverviewTool < ApplicationMCPTool
  INDICES = %w[NIFTY BANKNIFTY SENSEX].freeze

  tool_name 'get_market_overview'
  description 'Latest quote, regime, Supertrend, SMC bias and expiry for NIFTY, BANKNIFTY or SENSEX, ' \
              'plus session state and the current trade setup decision. Read-only; never places trades.'

  property :index, type: 'string', description: 'Index to inspect; omit for all three', enum: INDICES

  def perform
    snapshot = market_snapshot
    indices = snapshot['indices']
    indices = indices.select { |i| i['index_key'] == index } if index.present?

    render_json(
      generated_at: snapshot['generated_at'],
      mode: snapshot['mode'],
      session: snapshot['session'],
      indices: indices,
      market_context: snapshot['market_context'],
      setup: snapshot['setup'],
      warnings: snapshot['warnings']
    )
  end
end
