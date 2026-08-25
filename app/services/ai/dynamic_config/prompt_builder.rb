# frozen_string_literal: true

module Ai
  module DynamicConfig
    # Assembles the DynamicConfigAgent prompt: live regime + option-chain +
    # risk context (from ContextBuilder) plus the explicit allow-list of
    # tunable parameters (from ResultParser::KNOWN_PARAMS). Returns a prompt
    # string for Services::Ai::OllamaClient#generate.
    class PromptBuilder
      def self.call(context:)
        new(context: context).call
      end

      def initialize(context:)
        @context = context
        @index_key = context[:index_key]
      end

      def call
        <<~PROMPT.strip
          #{system_section}

          #{separator}
          CURRENT CONTEXT (#{@index_key})
          #{separator}

          #{context_section}

          #{separator}
          ALLOWED PARAMETERS
          #{separator}

          #{allowed_parameters_section}

          #{separator}
          EXAMPLE OUTPUT
          #{separator}

          #{example_section}

          Return ONLY valid JSON that matches the provided schema. No markdown formatting.
        PROMPT
      end

      private

      def separator
        '----------------------------------------'
      end

      def system_section
        <<~SYS.strip
          You are a live risk/sizing tuning engine for an automated Indian index
          (NIFTY/BANKNIFTY/SENSEX) options-buying system. Given the current market
          regime, option chain conditions, and today's risk state for #{@index_key},
          propose parameter adjustments for entries the system opens from now on.

          You MUST:
            - Only propose parameters from the ALLOWED PARAMETERS list, using the exact name
            - Set "index_key" to "#{@index_key}" for a per-index parameter, or "" for a global one
            - Include a confidence score (0.0-1.0); use a low score if the signal is weak
            - Leave a parameter out entirely rather than guess when data is missing

          You MUST NOT:
            - Invent parameter names not on the ALLOWED PARAMETERS list
            - Predict future prices or suggest discretionary trades
            - Propose a size/risk INCREASE when circuit_breaker_tripped is true or
              recent_consecutive_losses >= 2 — only a decrease or no change then
        SYS
      end

      def context_section
        JSON.pretty_generate(@context)
      end

      def allowed_parameters_section
        Ai::DynamicConfig::ResultParser::KNOWN_PARAMS.map do |name, spec|
          scope = spec[:per_index] ? 'per-index' : 'global'
          "- #{name} (#{scope}, range #{spec[:min]}..#{spec[:max]})"
        end.join("\n")
      end

      def example_section
        <<~EX.strip
          {
            "internal_reasoning": "Regime is choppy with elevated IV; reducing size and widening the premium band.",
            "market_assessment": { "regime": "choppy", "iv_environment": "high" },
            "parameter_changes": [
              {
                "parameter": "capital_alloc_pct",
                "index_key": "#{@index_key}",
                "current": 0.25,
                "suggested": 0.18,
                "reason": "Choppy regime plus high IV increases theta bleed risk — reduce size",
                "confidence": 0.8
              }
            ]
          }
        EX
      end
    end
  end
end
