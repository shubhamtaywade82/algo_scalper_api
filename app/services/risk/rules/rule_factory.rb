# frozen_string_literal: true

module Risk
  module Rules
    # Factory for creating rule engine with default rules
    class RuleFactory
      def self.create_engine(risk_config: {})
        rules = [
          SessionEndRule.new(config: risk_config),
          StopLossRule.new(config: risk_config),
          TakeProfitRule.new(config: risk_config),
          BracketLimitRule.new(config: risk_config),
          TimeBasedExitRule.new(config: risk_config),
          TrailingStopRule.new(config: risk_config),
          UnderlyingExitRule.new(config: risk_config)
        ]

        RuleEngine.new(rules: rules)
      end

      # Create a rule engine with custom rules
      # @param rules [Array<BaseRule>] Custom rules to use
      # @param include_defaults [Boolean] Whether to include default rules
      # @param risk_config [Hash] Risk configuration
      # @return [RuleEngine] Configured rule engine
      def self.create_custom_engine(rules: [], include_defaults: true, risk_config: {})
        all_rules = include_defaults ? create_engine(risk_config: risk_config).rules : []
        all_rules.concat(rules)
        RuleEngine.new(rules: all_rules)
      end
    end
  end
end
