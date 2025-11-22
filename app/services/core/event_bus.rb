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
      entry_filled: :entry_filled,
      sl_hit: :sl_hit,
      tp_hit: :tp_hit,
      structure_break: :structure_break,
      exit_triggered: :exit_triggered,
      risk_alert: :risk_alert,
      breakeven_lock: :breakeven_lock,
      trailing_triggered: :trailing_triggered,
      danger_zone: :danger_zone,
      volatility_spike: :volatility_spike,
      trend_flip: :trend_flip
    }.freeze

    def initialize
      @subscribers = Concurrent::Map.new { |h, k| h[k] = Concurrent::Array.new }
      @lock = Mutex.new
      @stats = {
        events_published: 0,
        events_delivered: 0,
        errors: 0
      }
    end

    # Subscribe to an event type
    # @param event_type [Symbol] Event type (e.g., :ltp, :sl_hit)
    # @param subscriber [Object, Proc] Subscriber object or proc
    # @param method_name [Symbol, nil] Method name to call on subscriber (if object)
    # @return [String] Subscription ID for unsubscribing
    def subscribe(event_type, subscriber = nil, method_name: nil, &block)
      raise ArgumentError, "Unknown event type: #{event_type}" unless EVENTS.value?(event_type)

      handler = if block
                  block
                elsif subscriber.is_a?(Proc)
                  subscriber
                elsif subscriber && method_name
                  ->(event) { subscriber.public_send(method_name, event) }
                elsif subscriber.respond_to?(:call)
                  ->(event) { subscriber.call(event) }
                else
                  raise ArgumentError, 'Must provide block, proc, or subscriber with method_name'
                end

      subscription_id = SecureRandom.uuid
      @subscribers[event_type] << {
        id: subscription_id,
        handler: handler,
        subscriber: subscriber
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

      @stats[:events_published] += 1
      notified = 0

      subscribers.each do |subscription|
        subscription[:handler].call(event)
        notified += 1
        @stats[:events_delivered] += 1
      rescue StandardError => e
        @stats[:errors] += 1
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

    # Unsubscribe all handlers for a specific subscriber object
    # @param subscriber [Object] Subscriber object to remove
    # @return [Integer] Number of subscriptions removed
    def unsubscribe_all(subscriber)
      removed = 0
      @subscribers.each_value do |subs|
        subs.delete_if do |sub|
          if sub[:subscriber] == subscriber
            removed += 1
            true
          else
            false
          end
        end
      end

      Rails.logger.debug { "[Core::EventBus] Unsubscribed all for #{subscriber.class.name} (#{removed} subscriptions)" } if removed.positive?
      removed
    end

    # Get statistics
    # @return [Hash] Statistics hash
    def stats
      @stats.dup
    end

    # Clear all subscriptions (for testing/cleanup)
    def clear
      @subscribers.clear
      @stats = {
        events_published: 0,
        events_delivered: 0,
        errors: 0
      }
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
