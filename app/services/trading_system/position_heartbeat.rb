# frozen_string_literal: true

module TradingSystem
  class PositionHeartbeat
    INTERVAL = 10 # seconds

    def initialize
      @running = false
      @thread  = nil
    end

    def start
      return if @running
      @running = true

      @thread = Thread.new do
        Thread.current.name = "position-heartbeat"

        loop do
          break unless @running
          begin
            Live::PositionIndex.instance.bulk_load_active!
            Live::PositionTrackerPruner.call
          rescue => e
            Rails.logger.error("[PositionHeartbeat] #{e.class} - #{e.message}")
          end

          sleep INTERVAL
        end
      end
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
    end
  end
end
