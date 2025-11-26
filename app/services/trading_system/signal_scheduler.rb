# frozen_string_literal: true

module TradingSystem
  class SignalScheduler < BaseService
    INTERVAL = 1 # seconds

    def initialize
      super
      @thread = nil
      @running = false
    end

    def start
      return if @running

      @running = true
      @thread = Thread.new { run_loop }
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
    end

    private

    def run_loop
      loop do
        break unless @running

        begin
          # Skip signal generation if market is closed (after 3:30 PM IST)
          if TradingSession::Service.market_closed?
            sleep 60 # Check every minute when market is closed
            next
          end

          perform_signal_scan
        rescue StandardError => e
          Rails.logger.error("[SignalScheduler] error: #{e.class} - #{e.message}")
        end

        sleep INTERVAL
      end
    end

    # Real logic (your existing scheduler call)
    def perform_signal_scan
      # Skip if market is closed
      return if TradingSession::Service.market_closed?

      # Signal::Scheduler processes indices in its start method's loop
      # For this wrapper, we just trigger one cycle of processing
      # by creating a temporary scheduler instance and processing indices
      indices = Array(AlgoConfig.fetch[:indices])
      return if indices.empty?

      scheduler = ::Signal::Scheduler.new(period: 1)
      indices.each do |idx_cfg|
        scheduler.send(:process_index, idx_cfg)
      rescue StandardError => e
        Rails.logger.error("[SignalScheduler] Error processing #{idx_cfg[:key]}: #{e.class} - #{e.message}")
      end
    end
  end
end
