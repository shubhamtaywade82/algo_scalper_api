# frozen_string_literal: true

module Positions
  module FinalPnl
    module_function

    def from_exit_price(entry_price:, quantity:, exit_price:, is_exited: true, position_side: 'long')
      return nil if exit_price.blank? || entry_price.blank? || quantity.to_i <= 0

      entry_bd = BigDecimal(entry_price.to_s)
      exit_bd = BigDecimal(exit_price.to_s)
      qty_bd = BigDecimal(quantity.to_i.to_s)
      capital = entry_bd * qty_bd
      return nil unless capital.positive?

      # Short: profit when price falls, so the price delta is inverted vs. long.
      price_delta = position_side.to_s == 'short' ? (entry_bd - exit_bd) : (exit_bd - entry_bd)
      gross_pnl = price_delta * qty_bd
      net_pnl = BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: is_exited)
      pnl_pct = net_pnl / capital

      {
        pnl: net_pnl,
        pnl_pct: pnl_pct,
        gross_pnl: gross_pnl
      }
    end
  end
end
