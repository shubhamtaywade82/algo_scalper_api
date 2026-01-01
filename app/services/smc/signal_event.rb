# frozen_string_literal: true

module Smc
  class SignalEvent
    attr_reader :instrument, :decision, :timeframe, :price, :reasons

    def initialize(instrument:, decision:, timeframe:, price:, reasons:)
      @instrument = instrument
      @decision = decision # :call / :put
      @timeframe = timeframe # "5m"
      @price = price
      @reasons = reasons # array of strings
    end

    def valid?
      %i[call put].include?(decision)
    end
  end
end

