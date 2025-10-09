# frozen_string_literal: true

require "singleton"
require "concurrent/map"

module Live
  class WsHub
    include Singleton

    def initialize
      @subscriptions = Concurrent::Map.new
      @lock = Mutex.new
      @callbacks_registered = false
    end

    def start!
      return if @started

      @lock.synchronize do
        return if @started

        register_lifecycle_callbacks
        delegate.start!
        resubscribe_all
        @started = true
      end
    end

    def subscribe(seg:, sid:)
      subscribe_option!(segment: seg, security_id: sid)
    end

    def subscribe_option!(segment:, security_id:)
      payload = normalize_payload(segment: segment, security_id: security_id)
      start!

      @subscriptions[payload[:key]] = payload
      delegate.subscribe(segment: payload[:segment], security_id: payload[:security_id])
      payload
    end

    def unsubscribe(seg:, sid:)
      unsubscribe_option!(segment: seg, security_id: sid)
    end

    def unsubscribe_option!(segment:, security_id:)
      payload = normalize_payload(segment: segment, security_id: security_id)
      @subscriptions.delete(payload[:key])
      return true unless delegate.running?

      delegate.unsubscribe(segment: payload[:segment], security_id: payload[:security_id])
    end

    def resubscribe_all
      return unless delegate.running?

      @subscriptions.each_value do |payload|
        delegate.subscribe(segment: payload[:segment], security_id: payload[:security_id])
      end
      true
    end

    def running?
      delegate.running?
    end

    def subscriptions
      @subscriptions.each_value.map { |payload| payload.slice(:segment, :security_id) }
    end

    private

    def register_lifecycle_callbacks
      return if @callbacks_registered

      delegate.on_connected { resubscribe_all }
      delegate.on_reconnected { resubscribe_all }
      @callbacks_registered = true
    end

    def delegate
      Live::MarketFeedHub.instance
    end

    def normalize_payload(segment:, security_id:)
      seg = segment.to_s
      sid = security_id.to_s
      { key: "#{seg}:#{sid}", segment: seg, security_id: sid }
    end
  end
end
