# frozen_string_literal: true

module Positions
  class IndexSync < ApplicationService
    ACTIVE_TRACKER_SET_KEY = 'positions:active_tracker_ids'

    def initialize(tracker:)
      @tracker = tracker
    end

    def register
      return unless tracker.active? && tracker.entry_price.present? && tracker.quantity.to_i.positive?

      Live::PositionIndex.instance.add(tracker.metadata_for_index)
      add_active_tracker_id
    rescue StandardError => e
      Rails.logger.warn("[Positions::IndexSync] #{e.class} - #{e.message}")
    end

    def unregister
      Live::PositionIndex.instance.remove(tracker.id, tracker.security_id)
      Live::RedisTickCache.instance.clear_tick(segment_key, tracker.security_id)
      Live::TickCache.delete(segment_key, tracker.security_id)
      remove_active_tracker_id
    rescue StandardError => e
      Rails.logger.warn("[Positions::IndexSync] #{e.class} - #{e.message}")
    end

    def refresh_if_relevant
      return unless relevant_index_change?

      unregister
      register
    end

    def self.clear_orphaned_redis_pnl!
      return unless PositionTracker.should_clear_orphaned?

      cache = Live::RedisPnlCache.instance
      active_ids = active_tracker_ids_from_redis
      stale_ids = []

      cache.each_tracker_key do |_key, tracker_id|
        stale_ids << tracker_id unless active_ids.include?(tracker_id)
      end

      stale_ids.each do |tracker_id|
        Rails.logger.warn("[Positions::IndexSync] Clearing orphaned Redis PnL cache for tracker #{tracker_id}")
        cache.clear_tracker(tracker_id)
      end

      PositionTracker.instance_variable_set(:@last_clear, Time.current)
    end

    def self.rebuild_active_tracker_set!
      ids = PositionTracker.active.pluck(:id).map(&:to_s)
      redis = redis_client
      redis.del(ACTIVE_TRACKER_SET_KEY)
      redis.sadd(ACTIVE_TRACKER_SET_KEY, ids) unless ids.empty?
    rescue StandardError => e
      Rails.logger.warn("[Positions::IndexSync] #{e.class} - #{e.message}")
    end

    def self.active_tracker_ids_from_redis
      redis_client.smembers(ACTIVE_TRACKER_SET_KEY).to_set
    rescue StandardError => e
      Rails.logger.warn("[Positions::IndexSync] #{e.class} - #{e.message}")
      Set.new
    end

    private

    attr_reader :tracker

    def relevant_index_change?
      tracker.saved_change_to_status? ||
        tracker.saved_change_to_security_id? ||
        tracker.saved_change_to_entry_price? ||
        tracker.saved_change_to_quantity?
    end

    def segment_key
      Positions::FeedSubscription.segment_key_for(tracker: tracker)
    end

    def add_active_tracker_id
      redis = self.class.send(:redis_client)
      redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
    rescue StandardError => e
      Rails.logger.warn("[Positions::IndexSync] #{e.class} - #{e.message}")
    end

    def remove_active_tracker_id
      redis = self.class.send(:redis_client)
      redis.srem(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
    rescue StandardError => e
      Rails.logger.warn("[Positions::IndexSync] #{e.class} - #{e.message}")
    end

    class << self
      private

      def redis_client
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      end
    end
  end
end
