# frozen_string_literal: true

module Policies
  # Abstract base for all Policy Objects.
  #
  # A Policy encapsulates a single business rule (or a coherent group of
  # related rules) so that service objects and models stay lean.
  # Policies are stateless value objects — they take their inputs at
  # construction time and expose a simple boolean interface.
  #
  # Subclasses must implement:
  #   • #permitted? → Boolean
  #   • #reasons    → Array<String>  (violations; empty when permitted)
  #
  # Usage:
  #   policy = MyPolicy.new(...)
  #   policy.permitted?     # => true / false
  #   policy.forbidden?     # => !permitted?
  #   policy.reasons        # => ["reason_code", ...]
  #   policy.authorize!     # raises PolicyViolationError if forbidden
  class BasePolicy
    # @return [Boolean] true when the action is allowed
    def permitted?
      raise NotImplementedError, "#{self.class} must implement #permitted?"
    end

    # @return [Boolean] true when the action is NOT allowed
    def forbidden?
      !permitted?
    end

    # @return [Array<String>] reason codes explaining why access is denied
    def reasons
      []
    end

    # Raise unless the policy permits the action.
    # @raise [PolicyViolationError]
    def authorize!
      return if permitted?

      raise PolicyViolationError, "Policy #{self.class.name} denied: #{reasons.join('; ')}"
    end

    class PolicyViolationError < StandardError; end
  end
end
