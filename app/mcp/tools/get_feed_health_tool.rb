# frozen_string_literal: true

class GetFeedHealthTool < ApplicationMCPTool
  tool_name 'get_feed_health'
  description 'DhanHQ market-feed connectivity: heartbeat status, per-index last tick age and data freshness. Read-only.'

  def perform
    snapshot = market_snapshot
    ticks = Array(snapshot['indices']).map do |i|
      {
        index_key: i['index_key'],
        last_tick_at: i.dig('quote', 'observed_at'),
        last_tick_age_seconds: i.dig('quote', 'age_seconds'),
        status: i.dig('quote', 'status')
      }
    end

    render_json(
      generated_at: snapshot['generated_at'],
      market_feed: snapshot.dig('health', 'components', 'market_feed'),
      last_ticks: ticks,
      freshness: snapshot['freshness']
    )
  end
end
