# frozen_string_literal: true

# Coerces numeric inputs for sizing and order commands without raising
# FloatDomainError when upstream values are NaN or Infinity (e.g. corrupt ticks).
module SafeNumeric
  module_function

  # @return [Integer] non-negative whole units (e.g. option quantity / lots)
  def to_non_negative_integer(value)
    return 0 if value.nil?

    return 0 if value.respond_to?(:finite?) && !value.finite?

    int =
      case value
      when Integer
        value
      when Float
        value.to_i
      when BigDecimal
        value.to_i
      else
        v = value.to_f
        return 0 unless v.finite?

        v.to_i
      end

    int.negative? ? 0 : int
  rescue FloatDomainError, RangeError, ArgumentError, TypeError
    0
  end
end
