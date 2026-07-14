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
            alert_rule_error(rule, context, e)
            # Continue to next rule on error — a broken rule must not silently disable
            # all exit checks for a position; remaining rules still get a chance to trigger.
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

      private

      def alert_rule_error(rule, _context, error)
        Notifications::TelegramNotifier.instance.notify_error(
          "RuleEngine: #{rule.name} raised #{error.class} - #{error.message} — skipped, other rules still evaluated",
          context: 'Risk::Rules::RuleEngine#evaluate'
        )
      rescue StandardError => e
        Rails.logger.error("[RuleEngine] alert_rule_error failed: #{e.message}")
      end
    end
  end
end
