# frozen_string_literal: true

module Dhan
  class SidecarListener
    FILLS_CHANNEL = 'dhan:execution:fills'
    EXITS_CHANNEL = 'dhan:execution:exits'

    class << self
      def start!
        return if @thread&.alive?

        @thread = Thread.new do
          Thread.current.name = 'dhan-sidecar-listener'
          listen_loop
        end
      end

      def stop!
        @thread&.kill
        @thread = nil
      end

      private

      def listen_loop
        redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
        redis.subscribe(FILLS_CHANNEL, EXITS_CHANNEL) do |on|
          on.message do |channel, message|
            payload = begin
              JSON.parse(message)
            rescue StandardError
              {}
            end
            case channel
            when FILLS_CHANNEL
              process_fill(payload)
            when EXITS_CHANNEL
              process_exit(payload)
            end
          end
        end
      rescue StandardError => e
        Rails.logger.error("[SidecarListener] Error: #{e.class} - #{e.message}")
        sleep 1
        retry
      end

      def process_fill(payload)
        Rails.logger.info("[SidecarListener] Fill received: #{payload.inspect}")
        return if payload['correlation_id'].blank?

        if payload['is_paper'] && defined?(PaperPosition)
          paper = PaperPosition.find_by(id: payload['position_id']) || PaperPosition.find_by(id: payload['correlation_id'])
          paper&.update!(status: 'active', entry_price: payload['fill_price'], quantity: payload['quantity'])
          ActionCable.server.broadcast('paper_positions', paper.as_json) if paper && defined?(ActionCable)
        elsif defined?(PositionTracker)
          tracker = PositionTracker.find_by(client_order_id: payload['correlation_id']) || PositionTracker.find_by(id: payload['position_id'])
          tracker&.update!(status: 'open', entry_price: payload['fill_price'], quantity: payload['quantity'])
          ActionCable.server.broadcast("positions_#{tracker.user_id}", tracker.as_json) if tracker.respond_to?(:user_id) && defined?(ActionCable)
        end
      end

      def process_exit(payload)
        Rails.logger.info("[SidecarListener] Exit received: #{payload.inspect}")
        return if payload['correlation_id'].blank? && payload['position_id'].blank?

        if payload['is_paper'] && defined?(PaperPosition)
          paper = PaperPosition.find_by(id: payload['position_id']) || PaperPosition.find_by(id: payload['correlation_id'])
          paper&.update!(status: 'closed', exit_price: payload['exit_price'], pnl: payload['pnl'])
        elsif defined?(PositionTracker)
          tracker = PositionTracker.find_by(client_order_id: payload['correlation_id']) || PositionTracker.find_by(id: payload['position_id'])
          tracker&.update!(status: 'closed', exit_price: payload['exit_price'], pnl: payload['pnl'], exit_reason: payload['reason'])
        end
      end
    end
  end
end
