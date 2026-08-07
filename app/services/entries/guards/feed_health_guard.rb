# frozen_string_literal: true

module Entries
  module Guards
    # Blocks entries when any required market-data feed is stale or has never synced.
    # LtpResolutionGuard only checks entry-LTP freshness narrowly; this covers the
    # broader feed set (ticks/positions/funds) that FeedHealthService already tracks.
    class FeedHealthGuard
      REQUIRED_FEEDS = %i[ticks positions funds].freeze

      class << self
        def call(_context)
          Live::FeedHealthService.instance.assert_healthy!(REQUIRED_FEEDS)
          EntryGuardPipeline::PASS
        rescue Live::FeedHealthService::FeedStaleError => e
          { blocked: "feed_stale: #{e.message}" }
        end
      end
    end
  end
end
