# frozen_string_literal: true

module Smc
  class SignalEvent
    attr_reader :instrument, :decision, :timeframe, :price, :reasons, :ai_analysis

    def initialize(instrument:, decision:, timeframe:, price:, reasons:, ai_analysis: nil)
      @instrument = instrument
      @decision   = decision # :call / :put / :no_trade
      @timeframe  = timeframe # "5m"
      @price      = price
      @reasons    = reasons   # array of strings
      @ai_analysis = ai_analysis # optional AI analysis string
    end

    def valid?
      # Valid if it's a trading signal OR if it has AI analysis (for no_trade notifications)
      %i[call put].include?(decision) || ai_analysis.present?
    end
  end
end
