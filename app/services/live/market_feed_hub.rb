# frozen_string_literal: true

require 'singleton'
require 'concurrent/array'
require 'concurrent/set'

module Live
  class MarketFeedHub
    include Singleton

    DEFAULT_MODE = :ticker

    def initialize
      @callbacks = Concurrent::Array.new
      @watchlist = nil
      @lock = Mutex.new
      @last_tick_at = nil
      @connection_state = :disconnected
      @last_error = nil
      @started_at = nil
      @subscribed_keys = Concurrent::Set.new # Track subscribed segment:security_id pairs
      @watchlist_keys = Concurrent::Set.new
    end

    def start!
      unless enabled?
        Rails.logger.warn('[MarketFeedHub] Not enabled - missing credentials (DHANHQ_CLIENT_ID/CLIENT_ID or DHANHQ_ACCESS_TOKEN/ACCESS_TOKEN)')
        return false
      end

      if running?
        Rails.logger.debug('[MarketFeedHub] Already running, skipping start')
        return true
      end

      @lock.synchronize do
        return true if running?

        @watchlist = load_watchlist || []
        refresh_watchlist_keys!
        Rails.logger.info("[MarketFeedHub] Loaded watchlist: #{@watchlist.count} instruments")

        @ws_client = build_client

        # Set up event handlers for connection monitoring
        setup_connection_handlers

        @ws_client.on(:tick) { |tick| handle_tick(tick) }
        @ws_client.start
        Rails.logger.info('[MarketFeedHub] WebSocket client started')

        @running = true
        @started_at = Time.current
        @connection_state = :connecting
        @last_error = nil

        # NOTE: Connection state will be updated to :connected when first tick is received
      end

      # Subscribe to watchlist OUTSIDE the lock to avoid deadlock
      # (subscribe_many calls ensure_running! which might try to acquire the lock)
      subscribe_watchlist

      Rails.logger.info("[MarketFeedHub] DhanHQ market feed started (watchlist=#{@watchlist.count} instruments)")
      true
    rescue StandardError => e
      Rails.logger.error("Failed to start DhanHQ market feed: #{e.class} - #{e.message}")
      stop!
      false
    end

    def stop!
      @lock.synchronize do
        @running = false
        @connection_state = :disconnected
        return unless @ws_client

        ws_client = @ws_client
        @ws_client = nil # Clear reference first to prevent new operations

        begin
          # Attempt graceful disconnect
          ws_client.disconnect! if ws_client.respond_to?(:disconnect!)
        rescue StandardError => e
          Rails.logger.warn("[MarketFeedHub] Error during disconnect: #{e.message}") if defined?(Rails.logger)
        end

        # Clear callbacks and subscription tracking
        @callbacks.clear
        @subscribed_keys.clear
        @watchlist_keys = Concurrent::Set.new
      end
    end

    def running?
      @running
    end

    # Returns true if the WebSocket connection is actually connected (not just started)
    def connected?
      return false unless running?
      return false unless @ws_client

      # Check if client has a connection state method
      if @ws_client.respond_to?(:connected?)
        @ws_client.connected?
      else
        # Fallback: check if we've received ticks recently (within last 30 seconds)
        @last_tick_at && (Time.current - @last_tick_at) < 30.seconds
      end
    rescue StandardError => _e
      # Rails.logger.warn("Error checking WebSocket connection: #{_e.message}")
      false
    end

    # Get connection health status
    def health_status
      {
        running: running?,
        connected: connected?,
        connection_state: @connection_state,
        started_at: @started_at,
        last_tick_at: @last_tick_at,
        ticks_received: @last_tick_at ? true : false,
        last_error: @last_error,
        watchlist_size: @watchlist&.count || 0
      }
    end

    # Diagnostic information for troubleshooting
    def diagnostics
      status = health_status
      result = {
        hub_status: status,
        credentials: {
          client_id: ENV['DHANHQ_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence ? '✅ Set' : '❌ Missing',
          access_token: ENV['DHANHQ_ACCESS_TOKEN'].presence || ENV['ACCESS_TOKEN'].presence ? '✅ Set' : '❌ Missing'
        },
        mode: mode,
        enabled: enabled?
      }

      if status[:last_tick_at]
        seconds_ago = (Time.current - status[:last_tick_at]).round(1)
        result[:last_tick] = "#{seconds_ago} seconds ago"
      else
        result[:last_tick] = 'Never'
      end

      result[:last_error_details] = status[:last_error] if status[:last_error]

      result
    end

    def subscribed?(segment:, security_id:)
      key = "#{segment}:#{security_id}"
      @subscribed_keys.include?(key)
    end

    def subscribe(segment:, security_id:)
      ensure_running!

      # Create composite key for tracking
      key = "#{segment}:#{security_id}"

      # Check if already subscribed
      if @subscribed_keys.include?(key)
        Rails.logger.debug { "[MarketFeedHub] Already subscribed to #{key}, skipping duplicate subscription" }
        return { segment: segment, security_id: security_id.to_s, already_subscribed: true }
      end

      # Subscribe via WebSocket
      @ws_client.subscribe_one(segment: segment, security_id: security_id.to_s)

      # Track subscription
      @subscribed_keys.add(key)

      { segment: segment, security_id: security_id.to_s, already_subscribed: false }
    end

    def subscribe_many(instruments)
      ensure_running!

      if instruments.empty?
        Rails.logger.warn('[MarketFeedHub] subscribe_many called with empty instruments list')
        return []
      end

      Rails.logger.debug { "[MarketFeedHub] subscribe_many called with #{instruments.count} instruments" }

      # Convert to the format expected by DhanHQ WebSocket client
      list = instruments.map do |instrument|
        if instrument.is_a?(Hash)
          { segment: instrument[:segment], security_id: instrument[:security_id].to_s }
        else
          { segment: instrument.segment, security_id: instrument.security_id.to_s }
        end
      end

      # Filter out already subscribed instruments
      new_subscriptions = list.reject do |item|
        key = "#{item[:segment]}:#{item[:security_id]}"
        @subscribed_keys.include?(key)
      end

      if new_subscriptions.empty?
        Rails.logger.info("[MarketFeedHub] All #{list.count} instruments were already subscribed (duplicates skipped)")
        return []
      end

      # Convert to format expected by DhanHQ client: ExchangeSegment and SecurityId keys
      normalized_list = new_subscriptions.map do |item|
        {
          ExchangeSegment: item[:segment] || item['segment'],
          SecurityId: (item[:security_id] || item['security_id']).to_s
        }
      end

      Rails.logger.info("[MarketFeedHub] Subscribing to #{new_subscriptions.count} instruments via WebSocket...")

      # Subscribe via WebSocket
      @ws_client.subscribe_many(normalized_list)

      # Track all new subscriptions
      new_subscriptions.each do |item|
        key = "#{item[:segment]}:#{item[:security_id]}"
        @subscribed_keys.add(key)
      end

      skipped_count = list.size - new_subscriptions.size
      if skipped_count > 0
        Rails.logger.info("[MarketFeedHub] Skipped #{skipped_count} duplicate subscriptions, subscribed to #{new_subscriptions.size} new instruments")
      else
        Rails.logger.info("[MarketFeedHub] Successfully subscribed to #{new_subscriptions.count} instruments")
      end

      new_subscriptions
    end

    def unsubscribe(segment:, security_id:)
      return { segment: segment, security_id: security_id.to_s, was_subscribed: false } unless running?

      # Create composite key for tracking
      key = "#{segment}:#{security_id}"
      was_subscribed = @subscribed_keys.include?(key)

      # Unsubscribe via WebSocket
      @ws_client.unsubscribe_one(segment: segment, security_id: security_id.to_s) if was_subscribed

      # Remove from tracking
      @subscribed_keys.delete(key)

      { segment: segment, security_id: security_id.to_s, was_subscribed: was_subscribed }
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

      # Convert to format expected by DhanHQ client: ExchangeSegment and SecurityId keys
      normalized_list = list.map do |item|
        {
          ExchangeSegment: item[:segment] || item['segment'],
          SecurityId: (item[:security_id] || item['security_id']).to_s
        }
      end

      @ws_client.unsubscribe_many(normalized_list)
      # Rails.logger.info("[MarketFeedHub] Batch unsubscribed from #{list.count} instruments")
      list
    end

    def on_tick(&block)
      raise ArgumentError, 'block required' unless block

      @callbacks << block
    end

    def subscribe_instrument(segment:, security_id:)
      return unless option_segment?(segment)
      return if watchlist_instrument?(segment, security_id)

      ensure_running!

      key = subscription_key(segment, security_id)
      @lock.synchronize do
        if @subscribed_keys.include?(key)
          Rails.logger.debug { "[MarketFeedHub] Option #{key} already subscribed" }
          return
        end

        begin
          @ws_client.subscribe_one(segment: segment, security_id: security_id.to_s)
          @subscribed_keys.add(key)
          Rails.logger.info("[MarketFeedHub] Option subscribed #{key}")
        rescue StandardError => e
          Rails.logger.error("[MarketFeedHub] subscribe_instrument failed for #{key}: #{e.class} - #{e.message}")
        end
      end
    end

    def unsubscribe_instrument(segment:, security_id:)
      return unless option_segment?(segment)
      return if watchlist_instrument?(segment, security_id)
      return unless running?

      key = subscription_key(segment, security_id)
      @lock.synchronize do
        return unless @subscribed_keys.include?(key)

        begin
          @ws_client.unsubscribe_one(segment: segment, security_id: security_id.to_s)
          Rails.logger.info("[MarketFeedHub] Option unsubscribed #{key}")
        rescue StandardError => e
          Rails.logger.error("[MarketFeedHub] unsubscribe_instrument failed for #{key}: #{e.class} - #{e.message}")
        ensure
          @subscribed_keys.delete(key)
        end
      end
    end

    private

    def enabled?
      # Always enabled - just check for credentials
      # Support both naming conventions: CLIENT_ID/DHANHQ_CLIENT_ID and ACCESS_TOKEN/DHANHQ_ACCESS_TOKEN
      client_id = ENV['DHANHQ_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
      access    = ENV['DHANHQ_ACCESS_TOKEN'].presence || ENV['ACCESS_TOKEN'].presence
      client_id.present? && access.present?
    end

    def ensure_running!
      start! unless running?
      raise 'DhanHQ market feed is not running' unless running?
    end

    def handle_tick(tick)
      # Update connection health indicators
      @last_tick_at = Time.current
      @connection_state = :connected

      # Update FeedHealthService
      begin
        Live::FeedHealthService.instance.mark_success!(:ticks)
      rescue StandardError
        nil
      end

      # puts tick  # Uncomment only for debugging - very noisy!
      # Log every tick (segment:security_id and LTP) for verification during development
      # # Rails.logger.info("[WS tick] #{tick[:segment]}:#{tick[:security_id]} ltp=#{tick[:ltp]} kind=#{tick[:kind]}")

      # Store in in-memory cache (primary)
      # Update TickCache for both ticker (with LTP) and prev_close (with prev_close) ticks
      # TickCache.put() handles merging of both types
      Live::TickCache.put(tick) if tick[:ltp].to_f.positive? || tick[:prev_close].to_f.positive?

      # # puts Live::TickCache.ltp(tick[:segment], tick[:security_id])
      # # Store in Redis for PnL tracking (secondary)
      # # Only store if we have valid segment, security_id, and LTP
      # if tick[:segment].present? && tick[:security_id].present? && tick[:ltp].present? && tick[:ltp].to_f.positive?
      #   begin
      #     if tick[:ltp].present? && tick[:ltp].to_f.positive?
      #       Live::RedisPnlCache.instance.store_tick(
      #         segment: tick[:segment],
      #         security_id: tick[:security_id].to_s,
      #         ltp: tick[:ltp],
      #         timestamp: Time.current
      #       )
      #     end
      #   rescue StandardError => e
      #     Rails.logger.debug { "[MarketFeedHub] Failed to store tick in Redis: #{e.message}" } if defined?(Rails.logger)
      #   end
      # end

      ActiveSupport::Notifications.instrument('dhanhq.tick', tick)

      @callbacks.each do |callback|
        safe_invoke(callback, tick)
      end
      # begin
      #   trackers = PositionTracker.active.where(security_id: tick[:security_id].to_s)
      #   trackers.each do |t|
      #     next unless t.entry_price && t.quantity
      #     pnl = (tick[:ltp].to_f - t.entry_price.to_f) * t.quantity
      #     pnl_pct = (tick[:ltp].to_f - t.entry_price.to_f) / t.entry_price.to_f
      #     Live::RedisPnlCache.instance.store_pnl(
      #       tracker_id: t.id,
      #       pnl: pnl,
      #       pnl_pct: pnl_pct,
      #       ltp: tick[:ltp],
      #       hwm: [t.high_water_mark_pnl.to_f, pnl].max,
      #       timestamp: Time.current
      #     )
      #   end
      # rescue => e
      #   Rails.logger.error("[MarketFeedHub] Failed to live-update Redis PnL: #{e.message}")
      # end
      # fast-path: drop empty/invalid ticks
      return unless tick[:ltp].to_f.positive? && tick[:security_id].present?

      # get in-memory trackers snapshot (array of metadata)
      trackers = Live::PositionIndex.instance.trackers_for(tick[:security_id].to_s)
      if trackers.empty?
        # nothing to do for this security
        return
      end

      # For each metadata push minimal payload (last-wins)
      trackers.each do |meta|
        # defensive checks
        next unless meta[:entry_price] && meta[:quantity] && meta[:quantity].to_i > 0

        Live::PnlUpdaterService.instance.cache_intermediate_pnl(
          tracker_id: meta[:id],
          ltp: tick[:ltp]
        )
      end
    end

    def safe_invoke(callback, payload)
      callback.call(payload)
    rescue StandardError => _e
      # Rails.logger.error("DhanHQ tick callback failed: #{_e.class} - #{_e.message}")
    end

    def subscribe_watchlist
      if @watchlist.empty?
        Rails.logger.warn('[MarketFeedHub] Watchlist is empty, skipping subscription')
        return
      end

      Rails.logger.info("[MarketFeedHub] Loading watchlist: #{@watchlist.count} instruments")

      # Use subscribe_many for efficient batch subscription (up to 100 instruments per message)
      # This will automatically deduplicate via subscribe_many
      result = subscribe_many(@watchlist)

      Rails.logger.info("[MarketFeedHub] Subscribed to watchlist (#{@watchlist.count} total, #{result.count} new subscriptions)")
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
                    seg = if record.respond_to?(:exchange_segment)
                            record.exchange_segment
                          elsif record.is_a?(Hash)
                            record[:exchange_segment] || record[:segment]
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

    def setup_connection_handlers
      # DhanHQ WebSocket client only supports :tick events
      # Connection/disconnection monitoring is handled via tick activity tracking
      # and connection state is inferred from tick reception

      # NOTE: The DhanHQ client handles reconnection internally
      # We track connection state via:
      # - Tick reception (sets @connection_state = :connected)
      # - Time-based fallback (connected? checks if ticks received recently)
      # - Explicit stop! calls (sets @connection_state = :disconnected)

      # Connection will be marked as :connected when first tick is received
      # in handle_tick method

      # Rails.logger.debug('[MarketFeedHub] Connection handlers: Using tick-based connection monitoring')
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

    def refresh_watchlist_keys!
      keys = Concurrent::Set.new
      Array(@watchlist).each do |item|
        seg = extract_segment(item)
        sid = extract_security_id(item)
        next unless seg && sid

        keys.add(subscription_key(seg, sid))
      end
      @watchlist_keys = keys
    end

    def extract_segment(item)
      if item.is_a?(Hash)
        item[:segment] || item[:exchange_segment]
      elsif item.respond_to?(:segment)
        item.segment
      end
    end

    def extract_security_id(item)
      if item.is_a?(Hash)
        item[:security_id]
      elsif item.respond_to?(:security_id)
        item.security_id
      end
    end

    def watchlist_instrument?(segment, security_id)
      return false unless segment && security_id

      key = subscription_key(segment, security_id)
      @watchlist_keys.include?(key)
    end

    def subscription_key(segment, security_id)
      "#{segment}:#{security_id}"
    end

    def option_segment?(segment)
      seg = segment.to_s.upcase
      seg.include?('FNO') || seg.include?('COMM') || seg.include?('CUR')
    end
  end
end
