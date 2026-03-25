# frozen_string_literal: true

module Positions
  class FeedSubscription < ApplicationService
    def initialize(tracker:)
      @tracker = tracker
    end

    def call
      subscribe
    end

    def self.unsubscribe(tracker:)
      new(tracker: tracker).unsubscribe
    end

    def self.segment_key_for(tracker:)
      tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
    end

    def unsubscribe
      hub = Live::MarketFeedHub.instance
      return unless hub.running?

      segment_key = self.class.segment_key_for(tracker: tracker)
      return unless segment_key && tracker.security_id
      return if segment_key == 'IDX_I'

      hub.unsubscribe(segment: segment_key, security_id: tracker.security_id)
    rescue StandardError => e
      Rails.logger.error("[Positions::FeedSubscription] #{e.class} - #{e.message}")
      nil
    end

    private

    attr_reader :tracker

    def subscribe
      segment_key = self.class.segment_key_for(tracker: tracker)
      return unless segment_key && tracker.security_id

      hub = Live::MarketFeedHub.instance
      hub.start! unless hub.running?
      hub.subscribe(segment: segment_key, security_id: tracker.security_id)
    rescue StandardError => e
      Rails.logger.error("[Positions::FeedSubscription] #{e.class} - #{e.message}")
      nil
    end
  end
end
