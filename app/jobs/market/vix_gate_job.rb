# frozen_string_literal: true

module Market
  class VixGateJob < ApplicationJob
    queue_as :background

    def perform
      return unless gate_enabled?

      Market::VixGate.evaluate!
    rescue StandardError => e
      Rails.logger.error("[Market::VixGateJob] #{e.class} - #{e.message}")
      raise
    end

    private

    def gate_enabled?
      AlgoConfig.fetch.dig(:market, :vix_gate, :enabled) == true
    rescue StandardError
      false
    end
  end
end
