# frozen_string_literal: true

module Derivatives
  class AtmOptions
    LIMIT = 5

    def self.call(symbol:, atm:, range: 100)
      Derivative
        .options
        .where(underlying_symbol: symbol.to_s.upcase)
        .current_expiry
        .where('ABS(strike_price - ?) <= ?', atm.to_f, range.to_f)
        .order(:strike_price)
        .limit(LIMIT)
    end
  end
end
