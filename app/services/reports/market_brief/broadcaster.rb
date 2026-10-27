# frozen_string_literal: true

module Reports
  module MarketBrief
    # Pushes Market Brief frames to the live page over ActionCable (MarketBriefChannel).
    #
    # Frames are sent only when something happened: an event, or a finished report.
    # Facts between those moments are served by the page's own poll, so the socket
    # carries no periodic traffic (solid_cable stores every frame in the cable DB).
    # Each frame carries the same payload the live endpoint returns, so the page can
    # swap it in directly.
    class Broadcaster
      CHANNEL = 'market_brief'

      class << self
        # @param events [Array<Hash>] events from the watcher's latest cycle
        def events(snapshot:, mode:, events:, now: Time.current)
          publish(type: 'event', events: events,
                  live: LiveBrief.payload_for(snapshot: snapshot, mode: mode, now: now))
        end

        # @param report [MarketBriefReport] a report whose generation has finished
        def report(report, now: Time.current)
          return if report&.snapshot.blank?

          publish(type: 'report', report_id: report.id,
                  live: LiveBrief.payload_for(snapshot: report.snapshot, mode: report.mode, now: now))
        end

        private

        def publish(frame)
          ActionCable.server.broadcast(CHANNEL, frame)
        rescue StandardError => e
          # A broadcast failure must never fail a trading-side cycle or a report build.
          Rails.logger.warn("[MarketBrief::Broadcaster] #{frame[:type]} broadcast failed: #{e.class} - #{e.message}")
        end
      end
    end
  end
end
