# frozen_string_literal: true

module Orders
  # Strict order-quantity resolution.
  #
  # Error-handling review 2026-09: a malformed sizing decision used to become
  # a real order for 1 unit (`qty.to_i.positive? ? qty.to_i : 1`), an
  # auto-sized order, or a silent liquidation of the whole position. A
  # quantity is now either explicitly valid or an Errors::InvalidQuantity —
  # never inferred.
  #
  # Accepted inputs:
  #   7           -> 7
  #   "7"         -> 7   (broker/config payloads arrive as strings)
  #   7.0         -> 7   (whole floats only)
  #   "7.0"       -> 7   (whole decimal strings only)
  #
  # Rejected (raises Errors::InvalidQuantity):
  #   nil, "", 0, -5, 2.5, "abc", "7abc", NaN, Infinity
  module Quantity
    WHOLE_NUMBER_PATTERN = /\A[+-]?\d+(\.0+)?\z/

    module_function

    # @param value [Object] raw quantity from caller/config
    # @param context [String, nil] description for the error message
    # @return [Integer] positive whole quantity
    # @raise [Errors::InvalidQuantity]
    def resolve!(value, context: nil)
      int = coerce(value)
      return int if int.is_a?(Integer) && int.positive?

      detail = "quantity must be a positive whole number, got #{value.inspect}"
      detail += " (#{context})" if context
      raise Errors::InvalidQuantity, detail
    end

    # Strict, non-raising variant for display paths: returns the resolved
    # quantity or nil. nil here means "unresolvable", never "zero".
    #
    # @return [Integer, nil]
    def resolve(value)
      int = coerce(value)
      int if int.is_a?(Integer) && int.positive?
    end

    class << self
      private

      # @return [Integer, nil] nil when the value is not a whole non-negative number
      def coerce(value)
        case value
        when Integer then value
        when Float, BigDecimal
          (value.respond_to?(:finite?) && value.finite? && (value % 1).zero?) ? value.to_i : nil
        when String
          stripped = value.strip
          stripped.match?(WHOLE_NUMBER_PATTERN) ? stripped.to_i : nil
        else
          nil
        end
      end
    end
  end
end
