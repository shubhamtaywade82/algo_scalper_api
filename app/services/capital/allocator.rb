# frozen_string_literal: true

require "bigdecimal"

module Capital
  class Allocator
    class << self
      def qty_for(index_cfg:, entry_price:)
        capital_available = available_cash
        return 0 if capital_available.zero?

        return 0 if entry_price.to_f <= 0

        allocation = capital_available * index_cfg[:capital_alloc_pct].to_f
        lot_size = index_cfg[:lot].to_i
        return 0 if lot_size <= 0

        risk_capital = capital_available * AlgoConfig.fetch.dig(:risk, :per_trade_risk_pct).to_f

        max_by_allocation = (allocation / (entry_price.to_f * lot_size)).floor * lot_size
        max_by_risk = (risk_capital / (entry_price.to_f * 0.30)).floor * lot_size

        quantity = [max_by_allocation, max_by_risk].min
        [[quantity, lot_size].max, lot_size * 100].min
      rescue StandardError => e
        Rails.logger.error("Capital::Allocator failed: #{e.class} - #{e.message}")
        0
      end

      private

      def available_cash
        data = DhanHQ::Models::Funds.fetch
        value = if data.respond_to?(:available_balance)
                  data.available_balance
                elsif data.respond_to?(:available_cash)
                  data.available_cash
                elsif data.is_a?(Hash)
                  data[:available_balance] || data[:available_cash]
                end

        return BigDecimal("0") if value.nil?

        value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
      rescue StandardError => e
        Rails.logger.error("Failed to fetch available cash: #{e.class} - #{e.message}")
        BigDecimal("0")
      end
    end
  end
end
