# frozen_string_literal: true

module Positions
  module FinalPnl
    module_function

    # meta['fee_model'] value stamped on trackers whose booked P&L uses statutory charges.
    STATUTORY_FEE_MODEL = 'statutory'

    # With +segment+ (and is_exited) the P&L is net of real per-leg NSE/BSE F&O charges —
    # brokerage, STT, exchange fee, GST, stamp duty, SEBI fee — the same figures Reports sums.
    # Without it the old flat per-order fee applies (live marks, estimates, pre-2026-11-02 rows).
    def from_exit_price(entry_price:, quantity:, exit_price:, is_exited: true, position_side: 'long', segment: nil)
      return nil if exit_price.blank? || entry_price.blank? || quantity.to_i <= 0

      entry_bd = BigDecimal(entry_price.to_s)
      exit_bd = BigDecimal(exit_price.to_s)
      qty_bd = BigDecimal(quantity.to_i.to_s)
      capital = entry_bd * qty_bd
      return nil unless capital.positive?

      # Short: profit when price falls, so the price delta is inverted vs. long.
      price_delta = position_side.to_s == 'short' ? (entry_bd - exit_bd) : (exit_bd - entry_bd)
      gross_pnl = price_delta * qty_bd
      charges = statutory_charges(entry_bd, exit_bd, qty_bd.to_i, position_side) if segment.present? && is_exited
      net_pnl = charges ? gross_pnl - charges : BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: is_exited)
      pnl_pct = net_pnl / capital

      {
        pnl: net_pnl,
        pnl_pct: pnl_pct,
        gross_pnl: gross_pnl,
        charges: charges
      }
    end

    # Recomputes a closed tracker's P&L under the fee model it was booked with, so a
    # reconciler does not "correct" statutory-charge trades back to the flat fee (or the reverse).
    def for_tracker(tracker)
      statutory = tracker.meta.is_a?(Hash) && tracker.meta['fee_model'] == STATUTORY_FEE_MODEL
      from_exit_price(
        entry_price: tracker.entry_price, quantity: tracker.quantity, exit_price: tracker.exit_price,
        is_exited: true, position_side: tracker.position_side, segment: (tracker.segment if statutory)
      )
    end

    def statutory_charges(entry_price, exit_price, quantity, position_side)
      entry_side, exit_side = position_side.to_s == 'short' ? %w[sell buy] : %w[buy sell]
      Orders::ChargesCalculator.call(side: entry_side, quantity: quantity, price: entry_price) +
        Orders::ChargesCalculator.call(side: exit_side, quantity: quantity, price: exit_price)
    end
  end
end
