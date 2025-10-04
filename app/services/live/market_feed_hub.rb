# frozen_string_literal: true

require "singleton"
require "concurrent/array"

module Live
  class MarketFeedHub
    include Singleton

    DEFAULT_MODE = :quote

    def initialize
      @callbacks = Concurrent::Array.new
      @watchlist = nil
      @lock = Mutex.new
    end

    def start!
      return unless enabled?
      return if running?

      @lock.synchronize do
        return if running?

        @watchlist = load_watchlist || []
        @ws_client = build_client
        @ws_client.on(:tick) { |tick| handle_tick(tick) }
        @ws_client.start
        subscribe_watchlist
        @running = true
      end

      Rails.logger.info("DhanHQ market feed started (mode=#{mode}, watchlist=#{@watchlist}).")
      true
    rescue StandardError => e
      Rails.logger.error("Failed to start DhanHQ market feed: #{e.class} - #{e.message}")
      stop!
      false
    end

    def stop!
      @lock.synchronize do
        @running = false
        return unless @ws_client

        begin
          @ws_client.disconnect!
        rescue StandardError => e
          Rails.logger.warn("Error while stopping DhanHQ market feed: #{e.message}")
        ensure
          @ws_client = nil
        end
      end
    end

    def running?
      @running
    end

    def subscribe(segment:, security_id:)
      ensure_running!
      payload = { segment: segment, security_id: security_id.to_s }
      @ws_client.subscribe_one(payload)
      payload
    end

    def unsubscribe(segment:, security_id:)
      return unless running?

      payload = { segment: segment, security_id: security_id.to_s }
      @ws_client.unsubscribe_one(payload)
      payload
    end

    def on_tick(&block)
      raise ArgumentError, "block required" unless block

      @callbacks << block
    end

    private

    def enabled?
      config.enabled && config.ws_enabled
    end

    def ensure_running!
      start! unless running?
      raise "DhanHQ market feed is not running" unless running?
    end

    def handle_tick(tick)
      Live::TickCache.put(tick)
      ActiveSupport::Notifications.instrument("dhanhq.tick", tick)
      @callbacks.each do |callback|
        safe_invoke(callback, tick)
      end
    end

    def safe_invoke(callback, payload)
      callback.call(payload)
    rescue StandardError => e
      Rails.logger.error("DhanHQ tick callback failed: #{e.class} - #{e.message}")
    end

    def subscribe_watchlist
      @watchlist.each do |item|
        @ws_client.subscribe_one(item)
      end
    end

    def load_watchlist
      raw = ENV.fetch("DHANHQ_WS_WATCHLIST", "")
               .split(/[;,\n]/)
               .map(&:strip)
               .reject(&:blank?)

      raw.filter_map do |entry|
        segment, security_id = entry.split(":", 2)
        next if segment.blank? || security_id.blank?

        { segment: segment, security_id: security_id }
      end
    end

    def build_client
      DhanHQ::WS::Client.new(mode: mode)
    end

    def mode
      allowed = %i[ticker quote full]
      selected = config.ws_mode
      allowed.include?(selected) ? selected : DEFAULT_MODE
    end

    def config
      Rails.application.config.x.dhanhq
    end
  end
end
