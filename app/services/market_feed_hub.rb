# frozen_string_literal: true

require "singleton"
require "concurrent/array"

class MarketFeedHub
  include Singleton

  DEFAULT_MODE = :quote

  def initialize
    @mutex = Mutex.new
    @callbacks = Concurrent::Array.new
  end

  def start!
    return unless enabled?
    return if running?

    @mutex.synchronize do
      return if running? || !enabled?

      @client = DhanHQ::WS::Client.new(mode: mode)
      @client.on(:tick) { |tick| handle_tick(tick) }
      @client.start
      subscribe_defaults
      @running = true
    end

    Rails.logger.info("MarketFeedHub started in #{mode} mode with #{default_subscriptions.count} default subscriptions.")
    true
  rescue StandardError => e
    Rails.logger.error("MarketFeedHub failed to start: #{e.class} - #{e.message}")
    stop!
    false
  end

  def stop!
    @mutex.synchronize do
      @running = false
      @client&.disconnect!
      @client = nil
    end
  rescue StandardError => e
    Rails.logger.warn("MarketFeedHub stop encountered: #{e.message}")
  end

  def running?
    @running
  end

  def subscribe_one(segment, security_id)
    ensure_running!
    payload = { segment: segment.to_s, security_id: security_id.to_s }
    @client.subscribe_one(**payload)
    payload
  end

  def unsubscribe_one(segment, security_id)
    return unless running? && @client

    payload = { segment: segment.to_s, security_id: security_id.to_s }
    @client.unsubscribe_one(**payload)
    payload
  end

  def on_tick(&block)
    raise ArgumentError, "block required" unless block

    @callbacks << block
  end

  private

  def ensure_running!
    start! unless running?
    raise "MarketFeedHub is not running" unless running?
  end

  def handle_tick(tick)
    TickCache.instance.put(tick)
    ActiveSupport::Notifications.instrument("dhanhq.tick", tick)
    broadcast_tick(tick)
    @callbacks.each { |callback| safe_invoke(callback, tick) }
  end

  def broadcast_tick(tick)
    return unless defined?(TickerChannel)

    TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, tick)
  end

  def safe_invoke(callback, payload)
    callback.call(payload)
  rescue StandardError => e
    Rails.logger.error("MarketFeedHub tick callback failed: #{e.class} - #{e.message}")
  end

  def subscribe_defaults
    default_subscriptions.each do |segment:, security_id:|
      @client.subscribe_one(segment: segment.to_s, security_id: security_id.to_s)
    end
  end

  def default_subscriptions
    @default_subscriptions ||= begin
      if defined?(Instrument) && Instrument.respond_to?(:where)
        Instrument.where(type: "Index").pluck(:exchange_segment, :security_id).map do |segment, security_id|
          { segment: segment, security_id: security_id }
        end
      else
        from_env = ENV.fetch("DHANHQ_WS_WATCHLIST", "")
                      .split(/[;,\n]/)
                      .map(&:strip)
                      .reject(&:blank?)
        from_env.filter_map do |entry|
          segment, security_id = entry.split(":", 2)
          next if segment.blank? || security_id.blank?

          { segment: segment, security_id: security_id }
        end
      end
    end
  end

  def mode
    allowed = %i[ticker quote full]
    requested = config&.ws_mode || DEFAULT_MODE
    allowed.include?(requested) ? requested : DEFAULT_MODE
  end

  def enabled?
    config&.enabled && config&.ws_enabled
  end

  def config
    Rails.application.config.x.dhanhq if Rails.application.config.x.respond_to?(:dhanhq)
  end
end
