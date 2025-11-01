# frozen_string_literal: true

require 'singleton'
require 'concurrent/array'

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

    def subscribe_many(instruments)
      ensure_running!
      return [] if instruments.empty?

      # Convert to the format expected by DhanHQ WebSocket client
      list = instruments.map do |instrument|
        if instrument.is_a?(Hash)
          { segment: instrument[:segment], security_id: instrument[:security_id].to_s }
        else
          { segment: instrument.segment, security_id: instrument.security_id.to_s }
        end
      end

      @ws_client.subscribe_many(req: mode, list: list)
      Rails.logger.info("[MarketFeedHub] Batch subscribed to #{list.count} instruments")
      list
    end

    def unsubscribe(segment:, security_id:)
      return unless running?

      @ws_client.unsubscribe_one(segment: segment, security_id: security_id.to_s)
      { segment: segment, security_id: security_id.to_s }
    end

    def unsubscribe_many(instruments)
      return [] unless running?
      return [] if instruments.empty?

      # Convert to the format expected by DhanHQ WebSocket client
      list = instruments.map do |instrument|
        if instrument.is_a?(Hash)
          { segment: instrument[:segment], security_id: instrument[:security_id].to_s }
        else
          { segment: instrument.segment, security_id: instrument.security_id.to_s }
        end
      end

      @ws_client.unsubscribe_many(req: mode, list: list)
      Rails.logger.info("[MarketFeedHub] Batch unsubscribed from #{list.count} instruments")
      list
    end

    def on_tick(&block)
      raise ArgumentError, 'block required' unless block

      @callbacks << block
    end

    private

    def enabled?
      # Always enabled - just check for credentials
      client_id = ENV['DHANHQ_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
      access    = ENV['DHANHQ_ACCESS_TOKEN'].presence || ENV['ACCESS_TOKEN'].presence
      client_id.present? && access.present?
    end

    def ensure_running!
      start! unless running?
      raise 'DhanHQ market feed is not running' unless running?
    end

    def handle_tick(tick)
      # pp tick
      # Log every tick (segment:security_id and LTP) for verification during development
      # Rails.logger.info("[WS tick] #{tick[:segment]}:#{tick[:security_id]} ltp=#{tick[:ltp]} kind=#{tick[:kind]}")
      Live::TickCache.put(tick)
      ActiveSupport::Notifications.instrument('dhanhq.tick', tick)
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
      return if @watchlist.empty?

      # Use subscribe_many for efficient batch subscription (up to 100 instruments per message)
      @ws_client.subscribe_many(req: mode, list: @watchlist)
      Rails.logger.info("[MarketFeedHub] Subscribed to #{@watchlist.count} instruments using subscribe_many")
    end

    def load_watchlist
      # Prefer DB watchlist if present; fall back to ENV for bootstrap-only
      if ActiveRecord::Base.connection.schema_cache.data_source_exists?('watchlist_items') &&
         WatchlistItem.exists?
        # Only load active watchlist items for subscription
        scope = WatchlistItem.active

        pairs = if scope.respond_to?(:order) && scope.respond_to?(:pluck)
                  scope.order(:segment, :security_id).pluck(:segment, :security_id)
                else
                  Array(scope).filter_map do |record|
                    seg = if record.respond_to?(:segment)
                            record.segment
                          elsif record.is_a?(Hash)
                            record[:segment]
                          end
                    sid = if record.respond_to?(:security_id)
                            record.security_id
                          elsif record.is_a?(Hash)
                            record[:security_id]
                          end
                    next if seg.blank? || sid.blank?

                    [seg, sid]
                  end
                end

                
        return pairs.map { |seg, sid| { segment: seg, security_id: sid } }
      end

      raw = ENV.fetch('DHANHQ_WS_WATCHLIST', '')
               .split(/[;\n,]/)
               .map(&:strip)
               .compact_blank

      raw.filter_map do |entry|
        segment, security_id = entry.split(':', 2)
        next if segment.blank? || security_id.blank?

        { segment: segment, security_id: security_id }
      end
    end

    def build_client
      DhanHQ::WS::Client.new(mode: mode)
    end

    def mode
      allowed = %i[ticker quote full]
      selected = config&.ws_mode || DEFAULT_MODE
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
