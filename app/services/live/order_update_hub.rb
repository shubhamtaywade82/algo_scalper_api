# frozen_string_literal: true

require 'singleton'
require 'concurrent/array'

module Live
  class OrderUpdateHub
    include Singleton

    def initialize
      @callbacks = Concurrent::Array.new
      @lock = Mutex.new
      @running = false
      @last_update_at = nil
      @connection_state = :disconnected
      @last_error = nil
      @watchdog_thread = nil
      @restarting = false
      @started_at = nil
    end

    def start!
      return unless enabled?
      return if running?

      @lock.synchronize do
        return if running?

        @ws_client = DhanHQ::WS::Orders::Client.new
        @ws_client.on(:update) { |payload| handle_update(payload) }
        @ws_client.start
        @running = true
        @started_at = Time.current
        @connection_state = :connecting
        @last_error = nil

        start_watchdog!
      end

      Rails.logger.info('[OrderUpdateHub] DhanHQ order update feed started (live mode only)')
      true
    rescue StandardError => e
      @last_error = e
      Rails.logger.error("[OrderUpdateHub] Failed to start DhanHQ order update feed: #{e.class} - #{e.message}")
      begin
        Live::FeedHealthService.instance.mark_failure!(:order_updates, error: e)
      rescue StandardError
        nil
      end
      stop!
      false
    end

    def stop!
      @lock.synchronize do
        @running = false
        @connection_state = :disconnected
        return unless @ws_client

        begin
          @ws_client.stop
        rescue StandardError => e
          Rails.logger.warn("[OrderUpdateHub] Error while stopping DhanHQ order update feed: #{e.message}")
        ensure
          @ws_client = nil
        end
      end
    end

    def running?
      @running
    end

    def health_status
      {
        running: running?,
        connection_state: @connection_state,
        started_at: @started_at,
        last_update_at: @last_update_at,
        last_error: @last_error
      }
    end

    def on_update(&block)
      raise ArgumentError, 'block required' unless block

      @callbacks << block
    end

    private

    def enabled?
      # Don't start in paper trading mode - paper mode handles positions locally via GatewayPaper
      # OrderUpdateHub is only needed for live trading to receive WebSocket updates from broker
      return false if paper_trading_enabled?

      # Check for credentials
      # Support both naming conventions: CLIENT_ID/DHAN_CLIENT_ID and ACCESS_TOKEN/DHAN_ACCESS_TOKEN
      client_id = ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
      access    = ENV['DHAN_ACCESS_TOKEN'].presence || ENV['ACCESS_TOKEN'].presence
      client_id.present? && access.present?
    end

    def paper_trading_enabled?
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
    rescue StandardError
      false
    end

    def config
      Rails.application.config.x.dhanhq
    end

    def handle_update(payload)
      normalized = normalize(payload)
      @last_update_at = Time.current
      @connection_state = :connected

      begin
        Live::FeedHealthService.instance.mark_success!(:order_updates)
      rescue StandardError
        nil
      end

      ActiveSupport::Notifications.instrument('dhanhq.order_update', normalized)
      @callbacks.each { |callback| safe_invoke(callback, normalized) }
    end

    def normalize(payload)
      return payload unless payload.is_a?(Hash)

      payload.deep_transform_keys { |key| key.to_s.underscore.to_sym }
    end

    def safe_invoke(callback, payload)
      callback.call(payload)
    rescue StandardError => e
      Rails.logger.error("[OrderUpdateHub] Order update callback failed: #{e.class} - #{e.message}")
    end

    def start_watchdog!
      return if @watchdog_thread&.alive?

      @watchdog_thread = Thread.new do
        Thread.current.name = 'ws-order-update-watchdog' if Thread.current.respond_to?(:name=)

        loop do
          sleep 5
          break unless running?

          check_connection_health!
        end
      end
    end

    def check_connection_health!
      return unless running?

      last_seen = @last_update_at
      return unless last_seen

      threshold = Live::FeedHealthService.instance.threshold_for(:order_updates)
      stale_for = Time.current - last_seen
      return unless stale_for > threshold

      Rails.logger.warn(
        "[OrderUpdateHub] Order updates feed stale for #{stale_for.round(1)}s (> #{threshold}s); restarting WebSocket client"
      )

      begin
        Live::FeedHealthService.instance.mark_failure!(:order_updates, error: RuntimeError.new('order_updates feed stale'))
      rescue StandardError
        nil
      end

      restart!
    rescue StandardError => e
      Rails.logger.error("[OrderUpdateHub] Failed to restart after stale order updates feed: #{e.class} - #{e.message}")
    end

    def restart!
      return if @restarting
      return unless running?

      @restarting = true
      stop!
      sleep 1
      start!
    ensure
      @restarting = false
    end
  end
end
