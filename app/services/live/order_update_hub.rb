# frozen_string_literal: true

require 'singleton'
require 'concurrent/array'

module Live
  class OrderUpdateHub
    include Singleton

    def initialize
      @callbacks = Concurrent::Array.new
      @lock = Mutex.new
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
      end

      Rails.logger.info('DhanHQ order update feed started.')
      true
    rescue StandardError => e
      Rails.logger.error("Failed to start DhanHQ order update feed: #{e.class} - #{e.message}")
      stop!
      false
    end

    def stop!
      @lock.synchronize do
        @running = false
        return unless @ws_client

        begin
          @ws_client.stop
        rescue StandardError => e
          Rails.logger.warn("Error while stopping DhanHQ order update feed: #{e.message}")
        ensure
          @ws_client = nil
        end
      end
    end

    def running?
      @running
    end

    def on_update(&block)
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

    def config
      Rails.application.config.x.dhanhq
    end

    def handle_update(payload)
      normalized = normalize(payload)
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
      Rails.logger.error("DhanHQ order update callback failed: #{e.class} - #{e.message}")
    end
  end
end
