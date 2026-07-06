# frozen_string_literal: true

module Strategies
  # Immutable read-only snapshot for strategy plugins.
  #
  # Built per invocation by {ContextBuilder}. Strategies never get access to
  # ActiveRecord, Redis, or any platform service — only this facade.
  class StrategyContext
    attr_reader :instrument_key, :candles, :indicators, :session,
                :position, :params, :clock, :config

    def initialize(instrument_key:, candles:, indicators:, session:,
                   position:, params:, clock:, config: {})
      @instrument_key = instrument_key
      @candles = candles
      @indicators = indicators
      @session = session
      @position = position
      @params = params
      @clock = clock
      @config = config
      freeze
    end
  end
end
