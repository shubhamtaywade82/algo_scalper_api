# frozen_string_literal: true

module Signal
  class Scheduler
    def initialize
      @indices = Array(AlgoConfig.fetch[:indices])
      @period = 30
      @thread = nil
    end

    def start!
      return if @thread&.alive?

      @thread = Thread.new do
        Thread.current.name = "signal-scheduler"
        loop do
          break if Risk::CircuitBreaker.instance.tripped?
          @indices.each_with_index do |index_cfg, idx|
            sleep(idx.zero? ? 0 : 5)
            Signal::Engine.run_for(index_cfg)
          end
          sleep(@period)
        end
      end
    end
  end
end
