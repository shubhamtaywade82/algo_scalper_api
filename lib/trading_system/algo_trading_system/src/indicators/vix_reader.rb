# frozen_string_literal: true

require_relative 'indicator_base'

module Indicators
  # Reads India VIX from market feed
  class VixReader < IndicatorBase
    attr_reader :value

    def initialize
      super()
      @value = nil
    end

    # The candle argument for VixReader should be a candle from the VIX instrument
    def update(candle)
      @value = candle.close
    end

    def ready?
      !@value.nil?
    end
  end
end
