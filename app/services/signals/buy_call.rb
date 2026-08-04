# frozen_string_literal: true

module Signals
  class BuyCall
    attr_reader :confidence, :reason, :metadata

    def initialize(confidence:, reason:, metadata: {})
      @confidence = confidence.to_f.clamp(0.0, 1.0)
      @reason = reason.to_s
      @metadata = metadata
      freeze
    end

    def buy_call? = true
    def buy_put?  = false
    def exit?     = false
    def hold?     = false

    def actionable? = true
  end
end
