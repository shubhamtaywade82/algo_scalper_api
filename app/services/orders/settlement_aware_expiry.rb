# frozen_string_literal: true

module Orders
  # Settlement-aware expiry logic.
  # Cash-settled: force-close on expiry day (current behavior).
  # Physical-settled: force-close T-1 (day before expiry) because physical
  # delivery requires closing positions before settlement date.
  class SettlementAwareExpiry
    def initialize(symbol:, settlement_type: "cash", expiry_date: nil)
      @symbol = symbol.to_s.upcase
      @settlement_type = settlement_type.to_s.downcase
      @expiry_date = expiry_date
    end

    def force_exit?
      return false unless effective_expiry_day?

      now = Time.current.in_time_zone("Asia/Kolkata")
      (now.hour == 15 && now.min >= 10) || now.hour > 15
    end

    def tighten_trailing?
      return false unless effective_expiry_day?

      now = Time.current.in_time_zone("Asia/Kolkata")
      (now.hour == 14 && now.min >= 45) || now.hour >= 15
    end

    def days_to_force_close
      @settlement_type == "physical" ? 1 : 0
    end

    private

    def effective_expiry_day?
      return physical_expiry_day? if @settlement_type == "physical"

      ExpiryRuleEngine.new(symbol: @symbol).send(:expiry_day?)
    end

    def physical_expiry_day?
      return false unless @expiry_date

      today = Time.current.in_time_zone("Asia/Kolkata").to_date
      (@expiry_date - 1) == today
    end
  end
end
