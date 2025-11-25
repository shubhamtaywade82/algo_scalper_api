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

      # This is equivalent to: Signal::Scheduler.instance.perform!
      ::Signal::Scheduler.new.perform!
    end
  end
end
