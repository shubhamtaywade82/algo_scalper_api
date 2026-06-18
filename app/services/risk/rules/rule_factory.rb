# frozen_string_literal: true

module Risk
  module Rules
    # Factory for creating rule engine with default rules
    class RuleFactory
      def self.exit_rules(risk_config = {})
        [
          StopLossRule.new(config: risk_config),
          AdaptiveTrailRule.new(config: risk_config),
          TakeProfitRule.new(config: risk_config),
          TimeBasedExitRule.new(config: risk_config)
        ]
      end

      def self.create_engine(risk_config: {})
        RuleEngine.new(rules: exit_rules(risk_config))
      end
    end
  end
end
