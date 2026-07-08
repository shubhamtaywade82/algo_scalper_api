# frozen_string_literal: true

module Strategies
  class Base
    class << self
      def timeframes = %w[1m]
      def instruments = %w[NIFTY]
      def params_schema = {}
    end

    def initialize(params: {})
      @params = params.freeze
    end

    def call(context)
      raise NotImplementedError, "#{self.class} must implement #call(context)"
    end

    def on_start(context) = nil
    def on_stop(context) = nil
    def on_position_opened(context) = nil
    def on_position_closed(context) = nil

    private

    attr_reader :params
  end
end
