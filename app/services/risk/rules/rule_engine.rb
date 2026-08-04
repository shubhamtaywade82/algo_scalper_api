# frozen_string_literal: true

module Risk
  module Rules
    # Rule engine that evaluates rules in priority order
    # First rule that triggers an exit wins, and evaluation stops
    class RuleEngine
      attr_reader :rules

      def initialize(rules: [])
        @rules = rules.sort_by(&:priority)
      end

      # Add a rule to the engine
      # @param rule [BaseRule] Rule to add
      # @return [RuleEngine] Self for chaining
      def add_rule(rule)
        @rules << rule
        @rules.sort_by!(&:priority)
        self
      end

      # Remove a rule from the engine
      # @param rule_class [Class] Rule class to remove
      # @return [RuleEngine] Self for chaining
      def remove_rule(rule_class)
        @rules.reject! { |r| r.is_a?(rule_class) }
        self
      end

      # Evaluate all rules against the given context
      # Rules are evaluated in priority order (lower priority number = higher priority)
      # First rule that triggers an exit wins, and evaluation stops
      # @param context [RuleContext] The rule evaluation context
      # @return [RuleResult] The result of rule evaluation
      def evaluate(context)
        return RuleResult.skip unless context.active?

        @rules.each do |rule|
          next unless rule.enabled?(context)

          begin
            result = rule.evaluate(context)

            # If we should continue (no_action or skip), move to next rule
            next if result.skip? || result.continue?

            # Attach rule name for traceability before returning
            result.rule_name = rule.name
            return result
          rescue StandardError => e
            Rails.logger.error(
              "[RuleEngine] Error evaluating rule #{rule.name}: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}"
            )
            # Continue to next rule on error
            next
          end
        end

        # No rule matched - default to no action
        RuleResult.no_action
      end

      # Get enabled rules
      # @param context [RuleContext] Optional context
      # @return [Array<BaseRule>] Array of enabled rules
      def enabled_rules(context = nil)
        @rules.select { |r| r.enabled?(context) }
      end

      # Get rule by class
      # @param rule_class [Class] Rule class to find
      # @return [BaseRule, nil] Found rule or nil
      def find_rule(rule_class)
        @rules.find { |r| r.is_a?(rule_class) }
      end
    end
  end
end
