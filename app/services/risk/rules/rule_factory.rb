# frozen_string_literal: true

module Risk
  module Rules
    # Factory for creating rule engine with default rules
    class RuleFactory
      def self.exit_rules(risk_config = {})
        [
          PortfolioFloorRule.new(config: risk_config),
          EmergencyPeakLossRule.new(config: risk_config),
          EarlyTrendFailureRule.new(config: risk_config),
          SmcNavigatorRule.new(config: risk_config),
          StopLossRule.new(config: risk_config),
          TimeRegimeExitRule.new(config: risk_config),
          PercentagePnlRule.new(config: risk_config),
          TakeProfitRule.new(config: risk_config),
          TrailingStopRule.new(config: risk_config),
          TimeBasedExitRule.new(config: risk_config),
          StructureInvalidationRule.new(config: risk_config),
          PremiumMomentumFailureRule.new(config: risk_config)
        ]
      end

      def self.create_engine(risk_config: {})
        RuleEngine.new(rules: exit_rules(risk_config))
      end
    end
  end
end
