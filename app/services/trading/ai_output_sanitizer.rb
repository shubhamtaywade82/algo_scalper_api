# frozen_string_literal: true

module Trading
  class AiOutputSanitizer
    class ViolatingAiOutputError < StandardError; end

    FORBIDDEN_ACTIONABLE_PATTERNS = [
      /\bATM\b/i,
      /\bstrike\b/i,
      /\bCE\b/i,
      /\bPE\b/i,
      /\bCALL\b/i,
      /\bPUT\b/i,
      /\bentry\b/i,
      /\bquantity\b/i,
      /\bqty\b/i,
      /\blot\b/i,
      /\bSL\b/i,
      /\bTP\b/i,
      /₹\s*\d+/,
      /\b\d{4,6}\b/ # strike-like numbers (coarse but intentional for blocked state)
    ].freeze

    FORBIDDEN_NON_SCALP_PATTERNS = [
      /\bscale\b/i,
      /\bscaling\b/i,
      /\bfull[_\s-]?deploy\b/i,
      /\bhold\b/i,
      /\bholding\b/i,
      /\brunner\b/i,
      /\btrend_minutes\b/i,
      /\btrend\b.*\bminutes\b/i
    ].freeze

    class << self
      # Enforces that AI output cannot violate the system permission state.
      #
      # @param permission [Symbol, String]
      # @param output [String, nil]
      # @return [String, nil] original output if valid
      # @raise [ViolatingAiOutputError]
      def validate!(permission:, output:)
        return output if output.nil?

        p = normalize_permission(permission)
        text = output.to_s

        case p
        when :blocked
          if violates_any?(text, FORBIDDEN_ACTIONABLE_PATTERNS)
            raise ViolatingAiOutputError,
                  'AI output includes actionable trading instructions while permission is :blocked'
          end
        when :execution_only
          if violates_any?(text, FORBIDDEN_NON_SCALP_PATTERNS)
            raise ViolatingAiOutputError,
                  'AI output includes holding/scaling content while permission is :execution_only'
          end
        end

        output
      end

      private

      def normalize_permission(permission)
        permission.to_s.strip.downcase.to_sym
      rescue StandardError
        :blocked
      end

      def violates_any?(text, patterns)
        patterns.any? { |rx| text.match?(rx) }
      end
    end
  end
end
