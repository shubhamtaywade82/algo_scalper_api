# frozen_string_literal: true

module Indicators
  # Abstract base class for all technical indicators
  class IndicatorBase
    def update(_candle)
      raise NotImplementedError, "#{self.class} must implement #update"
    end

    def value
      raise NotImplementedError, "#{self.class} must implement #value"
    end

    def ready?
      raise NotImplementedError, "#{self.class} must implement #ready?"
    end
  end
end
