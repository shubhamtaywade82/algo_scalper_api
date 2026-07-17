# frozen_string_literal: true

require 'singleton'
require 'concurrent/map'
require 'concurrent/array'

module Core
  # Central pub/sub event bus for NEMESIS V3 architecture
  # Provides internal event broadcasting for system components
  # Thread-safe singleton for high-performance tick processing
  # rubocop:disable Metrics/ClassLength
  class EventBus
    include Singleton

    # Event types
    EVENTS = {
      ltp: :ltp,
      sl_hit: :sl_hit,
      tp_hit: :tp_hit,
      exit_triggered: :exit_triggered,
      bracket_placed: :bracket_placed,
      bracket_modified: :bracket_modified,
      candle_closed: :candle_closed,
      strategy_signal: :strategy_signal,
      strategy_error: :strategy_error,
      strategy_status_change: :strategy_status_change
    }.freeze

    def initialize
      @subscribers = Concurrent::Map.new { |h, k| h[k] = Concurrent::Array.new }
      @lock = Mutex.new
    end

    # Subscribe to an event type
    # @param event_type [Symbol] Event type (e.g., :ltp, :sl_hit)
    # @return [String] Subscription ID for unsubscribing
    def subscribe(event_type, &block)
      raise ArgumentError, "Unknown event type: #{event_type}" unless EVENTS.value?(event_type)
      raise ArgumentError, 'Must provide a block' unless block

      subscription_id = SecureRandom.uuid
      @subscribers[event_type] << {
        id: subscription_id,
        handler: block
      }

      Rails.logger.debug { "[Core::EventBus] Subscribed to #{event_type} (#{subscription_id[0..7]})" }
      subscription_id
    end

    # Publish an event to all subscribers
    # @param event_type [Symbol] Event type
    # @param event [Object] Event object (must respond to #to_h or be a Hash)
    # @return [Integer] Number of subscribers notified
    def publish(event_type, event)
      raise ArgumentError, "Unknown event type: #{event_type}" unless EVENTS.value?(event_type)

      subscribers = @subscribers[event_type]
      return 0 if subscribers.empty?

      notified = 0

      subscribers.each do |subscription|
        subscription[:handler].call(event)
        notified += 1
      rescue StandardError => e
        Rails.logger.error(
          "[Core::EventBus] Error delivering #{event_type} to subscriber: #{e.class} - #{e.message}"
        )
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
      end

      notified
    end

    # Unsubscribe from an event
    # @param subscription_id [String] Subscription ID returned from subscribe
    # @return [Boolean] True if unsubscribed, false if not found
    def unsubscribe(subscription_id)
      found = false
      @subscribers.each_value do |subs|
        subs.delete_if do |sub|
          if sub[:id] == subscription_id
            found = true
            true
          else
            false
          end
        end
      end

      Rails.logger.debug { "[Core::EventBus] Unsubscribed (#{subscription_id[0..7]})" } if found
      found
    end

    # Clear all subscriptions (for testing/cleanup)
    def clear
      @subscribers.clear
      Rails.logger.debug('[Core::EventBus] Cleared all subscriptions')
    end

    # Get subscriber count for an event type
    # @param event_type [Symbol] Event type
    # @return [Integer] Number of subscribers
    def subscriber_count(event_type)
      @subscribers[event_type]&.size || 0
    end
  end
  # rubocop:enable Metrics/ClassLength
end
