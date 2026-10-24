# frozen_string_literal: true

module Entries
  module Guards
    class VixGateGuard
      include BaseGuard

      def self.call(context)
        return PASS unless gate_enabled?
        return PASS if Market::VixGate.entry_allowed?

        return unevaluated_block unless Market::VixGate.evaluated?

        vix = Market::VixGate.current_ltp
        ceiling = entry_ceiling
        { blocked: "India VIX gate: VIX=#{vix&.round(2) || 'n/a'} above entry ceiling #{ceiling}" }
      rescue Errors::Error => e
        # Domain failures (corrupt config) BLOCK — this guard exists to be a
        # risk gate; the previous `rescue StandardError -> PASS` let a corrupt
        # config document silently disable the entire VIX gate (wave 4).
        { blocked: "vix_gate_failed: #{e.class} - #{e.message}" }
      end

      # Absent/disabled section -> false (documented "gate off"); a corrupt
      # config document RAISES via AlgoConfig.fetch — never "unknown == off".
      def self.gate_enabled?
        AlgoConfig.fetch.dig(:market, :vix_gate, :enabled) == true
      end

      # Absent key -> documented 20.0 ceiling; a corrupt config document
      # raises instead of silently assuming a ceiling the operator never set.
      def self.entry_ceiling
        raw = AlgoConfig.fetch.dig(:market, :vix_gate, :entry_ceiling)
        return 20.0 if raw.nil?

        value = Float(raw)
        unless value.positive?
          raise Errors::ConfigurationError,
                "market.vix_gate.entry_ceiling must be a positive number (got #{raw.inspect})"
        end

        value
      rescue ArgumentError, TypeError => e
        raise Errors::ConfigurationError,
              "market.vix_gate.entry_ceiling is unparseable (#{raw.inspect}): #{e.message}"
      end

      def self.unevaluated_block
        { blocked: 'India VIX gate: awaiting first VIX evaluation (fail-closed)' }
      end
      private_class_method :unevaluated_block
    end
  end
end
