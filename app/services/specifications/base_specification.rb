# frozen_string_literal: true

module Specifications
  # Base class for specification pattern
  # Encapsulates business rules as composable specifications
  class BaseSpecification
    # Check if specification is satisfied
    # @param context [Object] Context object to evaluate against
    # @return [Boolean]
    def satisfied?(context)
      raise NotImplementedError, "#{self.class} must implement #satisfied?"
    end

    # Get failure reason if not satisfied
    # @param context [Object] Context object
    # @return [String, nil] Failure reason or nil if satisfied
    def failure_reason(context)
      satisfied?(context) ? nil : default_failure_reason
    end

    # Combine with another specification using AND logic
    # @param other [BaseSpecification] Other specification
    # @return [AndSpecification]
    def and(other)
      AndSpecification.new(self, other)
    end

    # Combine with another specification using OR logic
    # @param other [BaseSpecification] Other specification
    # @return [OrSpecification]
    def or(other)
      OrSpecification.new(self, other)
    end

    # Negate the specification
    # @return [NotSpecification]
    def not
      NotSpecification.new(self)
    end

    protected

    def default_failure_reason
      "#{self.class.name} not satisfied"
    end
  end

  # AND specification (both must be satisfied)
  class AndSpecification < BaseSpecification
    def initialize(spec1, spec2)
      @spec1 = spec1
      @spec2 = spec2
    end

    def satisfied?(context)
      @spec1.satisfied?(context) && @spec2.satisfied?(context)
    end

    def failure_reason(context)
      return @spec1.failure_reason(context) unless @spec1.satisfied?(context)
      return @spec2.failure_reason(context) unless @spec2.satisfied?(context)

      nil
    end
  end

  # OR specification (either must be satisfied)
  class OrSpecification < BaseSpecification
    def initialize(spec1, spec2)
      @spec1 = spec1
      @spec2 = spec2
    end

    def satisfied?(context)
      @spec1.satisfied?(context) || @spec2.satisfied?(context)
    end

    def failure_reason(context)
      return nil if satisfied?(context)

      "#{@spec1.failure_reason(context)} OR #{@spec2.failure_reason(context)}"
    end
  end

  # NOT specification (negation)
  class NotSpecification < BaseSpecification
    def initialize(spec)
      @spec = spec
    end

    def satisfied?(context)
      !@spec.satisfied?(context)
    end

    def failure_reason(context)
      satisfied?(context) ? nil : "#{@spec.class.name} was satisfied (should not be)"
    end
  end
end
