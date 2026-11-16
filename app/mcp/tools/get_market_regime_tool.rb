# frozen_string_literal: true

class GetMarketRegimeTool < ApplicationMCPTool
  INDICES = %w[NIFTY BANKNIFTY SENSEX].freeze

  tool_name 'get_market_regime'
  description 'Per-index market regime, Supertrend state, SMC structure and bias, and current expiry, ' \
              'plus the global market context. Read-only; never places trades.'

  property :index, type: 'string', description: 'Index to inspect; omit for all three', enum: INDICES

  def perform
    snapshot = market_snapshot
    indices = snapshot['indices']
    indices = indices.select { |i| i['index_key'] == index } if index.present?

    render_json(
      generated_at: snapshot['generated_at'],
      session: snapshot['session'],
      market_context: snapshot['market_context'],
      indices: indices
    )
  end
end
