# frozen_string_literal: true

module Investing
  # Raised when a sell would consume more shares than the holding's
  # available_quantity (T+1-settled quantity excluded) can cover
  # (TDD §6.5 LotReducer, §16 A1.9).
  class InsufficientQuantity < ValidationError; end
end
