# frozen_string_literal: true

module Signals
  class Exit
    attr_reader :reason, :metadata

    def initialize(reason:, metadata: {})
      @reason = reason.to_s
      @metadata = metadata
      freeze
    end

    def buy_call? = false
    def buy_put?  = false
    def exit?     = true
    def hold?     = false

    def actionable? = true
  end
end
