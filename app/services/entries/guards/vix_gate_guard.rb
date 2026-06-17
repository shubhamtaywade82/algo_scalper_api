# frozen_string_literal: true

module Entries
  module Guards
    class VixGateGuard
      include BaseGuard

      def self.call(context)
        return PASS unless gate_enabled?
        return PASS if Market::VixGate.entry_allowed?

        vix = Market::VixGate.current_ltp
        ceiling = entry_ceiling
        { blocked: "India VIX gate: VIX=#{vix&.round(2) || 'n/a'} above entry ceiling #{ceiling}" }
      rescue StandardError => e
        Rails.logger.warn("[VixGateGuard] #{e.class} - #{e.message}")
        PASS
      end

      def self.gate_enabled?
        AlgoConfig.fetch.dig(:market, :vix_gate, :enabled) == true
      rescue StandardError
        false
      end

      def self.entry_ceiling
        (AlgoConfig.fetch.dig(:market, :vix_gate, :entry_ceiling) || 20.0).to_f
      rescue StandardError
        20.0
      end
    end
  end
end
