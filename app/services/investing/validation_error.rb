# frozen_string_literal: true

module Investing
  # Raised when caller input violates an Investing-domain rule: duplicate
  # portfolio names, unknown mandates, live-mode gate closed, negative cash,
  # quantity exceeding available holdings, and so on (TDD §6.1, §6.5).
  class ValidationError < Error; end
end
