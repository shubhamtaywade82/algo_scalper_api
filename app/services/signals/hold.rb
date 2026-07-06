# frozen_string_literal: true

module Signals
  class Hold
    attr_reader :reason

    def initialize(reason: nil)
      @reason = reason&.to_s
      freeze
    end

    def buy_call? = false
    def buy_put?  = false
    def exit?     = false
    def hold?     = true

    def actionable? = false
  end
end
