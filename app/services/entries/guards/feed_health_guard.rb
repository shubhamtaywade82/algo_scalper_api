# frozen_string_literal: true

module Entries
  module Guards
    # Blocks entries when any required market-data feed is stale or has never synced.
    # LtpResolutionGuard only checks entry-LTP freshness narrowly; this covers the
    # broader feed set (ticks/positions/funds) that FeedHealthService already tracks.
    class FeedHealthGuard
      REQUIRED_FEEDS = %i[ticks positions].freeze
      PAPER_REQUIRED_FEEDS = %i[ticks].freeze

      class << self
        def call(context = {})
          feeds = paper_mode?(context) ? PAPER_REQUIRED_FEEDS : REQUIRED_FEEDS
          Live::FeedHealthService.instance.assert_healthy!(feeds)
          EntryGuardPipeline::PASS
        rescue Live::FeedHealthService::FeedStaleError => e
          { blocked: "feed_stale: #{e.message}" }
        end

        private

        def paper_mode?(context)
          return context[:paper_trading] if context.key?(:paper_trading)
          return context[:paper_mode] if context.key?(:paper_mode)

          AlgoConfig.paper_trading_enabled?
        end
      end
    end
  end
end
