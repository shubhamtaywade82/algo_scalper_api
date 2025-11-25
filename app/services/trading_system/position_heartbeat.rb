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
        Thread.current.name = 'position-heartbeat'

        loop do
          break unless @running

          begin
            # Skip heartbeat if market is closed and no active positions
            if TradingSession::Service.market_closed?
              active_count = PositionTracker.active.count
              if active_count.zero?
                # Market closed and no active positions - sleep longer
                sleep 60 # Check every minute when market is closed and no positions
                next
              end
              # Market closed but positions exist - continue heartbeat (needed for index updates)
            end

            Live::PositionIndex.instance.bulk_load_active!
            Live::PositionTrackerPruner.call
          rescue StandardError => e
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
