# frozen_string_literal: true

require 'singleton'

module Signal
  # Coordinates periodic signal evaluation for configured indices.
  #
  # This scheduler runs in a background thread, executing `Signal::Engine.run_for`
  # at a fixed cadence for each configured index. It is a singleton to avoid
  # spawning duplicate loops on code reloads.
  class Scheduler
    include Singleton

    def initialize
      @period = 30
      @thread = nil
      @lock = Mutex.new
    end

    # Starts the scheduler thread if it is not already running.
    #
    # @return [void]
    def start!
      @lock.synchronize do
        return if running?

        indices = Array(AlgoConfig.fetch[:indices])
        @thread = Thread.new do
          Thread.current.name = 'signal-scheduler'
          loop do
            # Circuit breaker check disabled - removed per requirement
            # break if Risk::CircuitBreaker.instance.tripped?

            indices.each_with_index do |index_cfg, idx|
              sleep(idx.zero? ? 0 : 5)
              Signal::Engine.run_for(index_cfg)
            end

            sleep(@period)
          end
        ensure
          @lock.synchronize { @thread = nil }
        end
      end
    end

    # Stops the scheduler thread if it is running.
    #
    # @return [void]
    def stop!
      thread = nil

      @lock.synchronize do
        thread = @thread
        @thread = nil
      end

      return unless thread

      thread.kill
      thread.join(2)
    rescue StandardError => e
      # Rails.logger.warn("Signal::Scheduler stop encountered: #{e.class} - #{e.message}")
    end

    # Indicates whether the scheduler thread is alive.
    #
    # @return [Boolean]
    def running?
      @thread&.alive?
    end
  end
end
