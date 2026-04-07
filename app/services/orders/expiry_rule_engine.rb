# frozen_string_literal: true

module Orders
  class ExpiryRuleEngine
    def initialize(symbol: nil)
      @symbol = symbol.to_s.upcase
    end

    def force_exit?
      return false unless expiry_day?

      now = Time.current.in_time_zone('Asia/Kolkata')
      # after 15:10 force exit
      (now.hour == 15 && now.min >= 10) || now.hour > 15
    end

    def tighten_trailing?
      return false unless expiry_day?

      now = Time.current.in_time_zone('Asia/Kolkata')
      # after 14:45 tighten SL
      (now.hour == 14 && now.min >= 45) || (now.hour >= 15)
    end

    private

    def expiry_day?
      Market::ExpiryChecker.expiry_today?(@symbol)
    end
  end
end
