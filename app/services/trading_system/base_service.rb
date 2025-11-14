# frozen_string_literal: true

module TradingSystem
  class BaseService
    def start
      raise NotImplementedError, "#{self.class} must implement #start"
    end

    def stop
      raise NotImplementedError, "#{self.class} must implement #stop"
    end
  end
end
