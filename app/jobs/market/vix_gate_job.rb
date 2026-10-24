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

    # Flag absent -> gate off (documented). A corrupt config document
    # propagates — perform's rescue logs and re-raises so the job retries
    # instead of the VIX risk gate silently reading as disabled (wave 3).
    def gate_enabled?
      AlgoConfig.fetch.dig(:market, :vix_gate, :enabled) == true
    end
  end
end
