# frozen_string_literal: true

module Reports
  module MarketBrief
    # Today's market events per mode, shown in the page's timeline.
    #
    # Written only by the trading daemon's watcher, and only when an event fires
    # (a handful per session), so the shared cache sees a low write rate. Entries
    # from earlier trading dates are dropped on read.
    class EventLog
      CAP = 50
      TTL = 2.days

      class << self
        def append(mode, events)
          return if events.blank?

          Rails.cache.write(key(mode), (recent(mode) + events).last(CAP), expires_in: TTL)
        rescue StandardError => e
          Rails.logger.warn("[MarketBrief::EventLog] append failed: #{e.class}")
        end

        # @return [Array<Hash>] today's events, oldest first
        def recent(mode, today: Time.current.in_time_zone(TradingSession::Service::IST_TIMEZONE).to_date)
          Array(Rails.cache.read(key(mode))).select do |event|
            at = Time.zone.parse(event['at'].to_s)
            at && at.in_time_zone(TradingSession::Service::IST_TIMEZONE).to_date == today
          end
        rescue StandardError => e
          Rails.logger.warn("[MarketBrief::EventLog] read failed: #{e.class}")
          []
        end

        private

        def key(mode)
          "market_brief:events:#{mode}"
        end
      end
    end
  end
end
