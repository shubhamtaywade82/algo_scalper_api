module TradingSystem
  class OrderRouter
    def initialize
      @running = false
    end

    def start; @running = true; end
    def stop;  @running = false; end

    def exit_market(tracker)
      Orders::Manager.new(tracker).close_position!
    end
  end
end
