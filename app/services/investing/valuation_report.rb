# frozen_string_literal: true

module Investing
  # Valuation snapshot consumed by the allocation services (TDD §6.2/§7.1).
  #
  # Spike form: built directly by callers (specs, console) with per-sleeve
  # values. Phase 1 replaces the producer with Investing::Portfolios::Valuation
  # (prices -> holdings -> sleeve aggregation); Calculator's contract —
  # total_value / sleeve_values / unclassified_value — stays identical, so
  # the allocation specs keep running unchanged.
  class ValuationReport
    attr_reader :total_value, :sleeve_values, :unclassified_value, :as_at

    # @param total_value [Numeric] portfolio value including cash (INR)
    # @param sleeve_values [Hash{String|Symbol => Numeric}] value per sleeve_key
    # @param unclassified_value [Numeric] value of holdings without a sleeve
    # @param as_at [Time]
    def initialize(total_value:, sleeve_values: {}, unclassified_value: 0, as_at: Time.current)
      @total_value = BigDecimal(total_value.to_s)
      @sleeve_values = sleeve_values.to_h { |k, v| [k.to_s, BigDecimal(v.to_s)] }
      @unclassified_value = BigDecimal(unclassified_value.to_s)
      @as_at = as_at
    end

    def sleeve_value(key)
      sleeve_values[key.to_s]
    end
  end
end
