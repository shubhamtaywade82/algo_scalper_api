# frozen_string_literal: true

module Risk
  module Rules
    # Result of rule evaluation
    # Indicates what action should be taken based on the rule evaluation
    class RuleResult
      attr_reader :action, :reason, :metadata

      # Action types
      EXIT = :exit
      NO_ACTION = :no_action
      SKIP = :skip

      def initialize(action:, reason: nil, metadata: {})
        @action = action
        @reason = reason
        @metadata = metadata || {}
      end

      # Create a result indicating exit should be triggered
      # @param reason [String] Reason for exit
      # @param metadata [Hash] Additional metadata
      # @return [RuleResult] Exit result
      def self.exit(reason:, metadata: {})
        new(action: EXIT, reason: reason, metadata: metadata)
      end

      # Create a result indicating no action should be taken
      # @return [RuleResult] No action result
      def self.no_action
        new(action: NO_ACTION)
      end

      # Create a result indicating rule should be skipped
      # @return [RuleResult] Skip result
      def self.skip
        new(action: SKIP)
      end

      # Check if exit should be triggered
      # @return [Boolean] true if exit action, false otherwise
      def exit?
        action == EXIT
      end

      # Check if no action should be taken
      # @return [Boolean] true if no action, false otherwise
      def no_action?
        action == NO_ACTION
      end

      # Check if rule should be skipped
      # @return [Boolean] true if skip, false otherwise
      def skip?
        action == SKIP
      end

      # Check if rule evaluation should continue (not exit and not skip)
      # @return [Boolean] true if should continue, false otherwise
      def continue?
        no_action?
      end
    end
  end
end
