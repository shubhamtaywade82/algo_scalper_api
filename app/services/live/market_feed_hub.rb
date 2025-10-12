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
      @ws_client.subscribe_one(segment: segment, security_id: security_id.to_s)
      { segment: segment, security_id: security_id.to_s }
    end

    def unsubscribe(segment:, security_id:)
      return unless running?

      @ws_client.unsubscribe_one(segment: segment, security_id: security_id.to_s)
      { segment: segment, security_id: security_id.to_s }
    end

    def on_tick(&block)
      raise ArgumentError, "block required" unless block

      @callbacks << block
    end

    private

    def enabled?
      pp config
      # Prefer app config if present; otherwise derive from ENV credentials
      cfg = config
      if cfg && cfg.respond_to?(:enabled) && cfg.respond_to?(:ws_enabled)
        return (cfg.enabled && cfg.ws_enabled)
      end

      client_id = ENV["DHANHQ_CLIENT_ID"].presence || ENV["CLIENT_ID"].presence
      access    = ENV["DHANHQ_ACCESS_TOKEN"].presence || ENV["ACCESS_TOKEN"].presence
      client_id.present? && access.present?
    end

    def ensure_running!
      start! unless running?
      raise "DhanHQ market feed is not running" unless running?
    end

    def handle_tick(tick)
      pp tick
      # Log every tick (segment:security_id and LTP) for verification during development
      Rails.logger.info("[WS tick] #{tick[:segment]}:#{tick[:security_id]} ltp=#{tick[:ltp]} kind=#{tick[:kind]}")
      Live::TickCache.put(tick)
      ActiveSupport::Notifications.instrument("dhanhq.tick", tick)
      # Broadcast to Action Cable subscribers if channel is present
      if defined?(::TickerChannel)
        ::TickerChannel.broadcast_to(::TickerChannel::CHANNEL_ID, tick)
      end
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
        @ws_client.subscribe_one(segment: item[:segment], security_id: item[:security_id])
      end
    end

    def load_watchlist
      # Prefer DB watchlist if present; fall back to ENV for bootstrap-only
      if ActiveRecord::Base.connection.schema_cache.data_source_exists?("watchlist_items") &&
         WatchlistItem.exists?
        return WatchlistItem.order(:segment, :security_id).pluck(:segment, :security_id).map do |seg, sid|
          { segment: seg, security_id: sid }
        end
      end

      raw = ENV.fetch("DHANHQ_WS_WATCHLIST", "")
               .split(/[;\n,]/)
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
      selected = (config&.ws_mode || DEFAULT_MODE)
      allowed.include?(selected) ? selected : DEFAULT_MODE
    end

    def config
      return nil unless Rails.application.config.respond_to?(:x)
      x = Rails.application.config.x
      return nil unless x.respond_to?(:dhanhq)
      cfg = x.dhanhq
      cfg.is_a?(ActiveSupport::InheritableOptions) ? cfg : nil
    rescue StandardError
      nil
    end
  end
end
