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

    private

    attr_reader :params
  end
end
