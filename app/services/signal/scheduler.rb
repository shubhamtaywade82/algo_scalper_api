# frozen_string_literal: true

module Signal
  class Scheduler
    DEFAULT_PERIOD = 30 # seconds

    def initialize(period: DEFAULT_PERIOD)
      @period = period
      @running = false
      @thread  = nil
      @mutex   = Mutex.new
    end

    def start
      return if @running

      @mutex.synchronize do
        return if @running

        @running = true
      end

      indices = Array(AlgoConfig.fetch[:indices])

      @thread = Thread.new do
        Thread.current.name = 'signal-scheduler'

        loop do
          break unless @running

          begin
            indices.each_with_index do |idx_cfg, idx|
              break unless @running

              sleep(idx.zero? ? 0 : 5)
              Signal::Engine.run_for(idx_cfg)
            end
          rescue StandardError => e
            Rails.logger.error("[SignalScheduler] #{e.class} - #{e.message}")
          end

          sleep @period
        end
      end
    end

    def stop
      @mutex.synchronize { @running = false }
      @thread&.kill
      @thread = nil
    end
  end
end
