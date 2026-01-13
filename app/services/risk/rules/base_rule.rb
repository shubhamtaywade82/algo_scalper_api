# frozen_string_literal: true

module Risk
  module Rules
    # Base class for all risk and position management rules
    # Each rule evaluates a specific condition and returns a RuleResult
    class BaseRule
      # Priority order: lower numbers = higher priority
      # Rules are evaluated in priority order, and first matching rule wins
      PRIORITY = 100

      attr_reader :config

      def initialize(config: {})
        @config = config || {}
      end

      # Evaluate the rule against the given context
      # @param context [Risk::Rules::RuleContext] The rule evaluation context
      # @return [Risk::Rules::RuleResult] The result of rule evaluation
      def evaluate(context)
        raise NotImplementedError, "#{self.class} must implement #evaluate"
      end

      # Get the priority of this rule (lower = higher priority)
      # @return [Integer] Priority value
      def priority
        self.class::PRIORITY
      end

      # Get the name of this rule
      # @return [String] Rule name
      def name
        self.class.name.demodulize.underscore.gsub('_rule', '')
      end

      # Check if this rule is enabled
      # @return [Boolean] true if enabled, false otherwise
      def enabled?
        config.fetch(:enabled, true)
      end

      protected

      # Helper to create a rule result indicating exit should be triggered
      # @param reason [String] Reason for exit
      # @param metadata [Hash] Additional metadata
      # @return [Risk::Rules::RuleResult] Exit result
      def exit_result(reason:, metadata: {})
        Risk::Rules::RuleResult.exit(reason: reason, metadata: metadata)
      end

      # Helper to create a rule result indicating no action
      # @return [Risk::Rules::RuleResult] No action result
      def no_action_result
        Risk::Rules::RuleResult.no_action
      end

      # Helper to create a rule result indicating rule should be skipped
      # @return [Risk::Rules::RuleResult] Skip result
      def skip_result
        Risk::Rules::RuleResult.skip
      end
    end
  end
end
