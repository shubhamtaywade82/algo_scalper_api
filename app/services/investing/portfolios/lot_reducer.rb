# frozen_string_literal: true

require "bigdecimal"

module Investing
  module Portfolios
    # FIFO lot consumption on sells — the accounting heart of cost basis
    # (TDD §6.5). Deterministic ordering: (acquired_on, id) ASC — never DB
    # default order, never random.
    #
    # Mutations (inside the CALLER's transaction, so a fill ingestion can
    # wrap lots + holdings + cash + transactions atomically, §10.4):
    #   * each consumed lot's remaining_quantity decremented
    #   * holding.available_quantity decremented by the total taken
    #
    # holding.quantity / average_cost_price updates belong to the fill
    # ingestion service (§10.4 / A2.8, Phase 2), not to this class.
    class LotReducer
      ZERO = BigDecimal("0")

      LotConsumption = Struct.new(:lot, :quantity_taken, keyword_init: true)

      # @param holding [InvestmentHolding]
      # @param quantity [Numeric, String] quantity being sold
      # @param trade_date [Date, nil] informational; the T+1 guard is
      #        expressed by available_quantity already excluding t1_quantity
      # @return [Array<LotConsumption>] oldest lot first, deterministic
      # @raise [Investing::InsufficientQuantity] when quantity > available
      def consume_fifo!(holding, quantity:, trade_date: nil)
        to_take = BigDecimal(quantity.to_s)
        raise ValidationError, "quantity must be positive (got #{to_take})" if to_take <= ZERO

        available = BigDecimal(holding.available_quantity.to_s)
        if to_take > available
          raise InsufficientQuantity,
                "cannot sell #{to_take}: available_quantity is #{available} " \
                "(t1_quantity #{holding.t1_quantity} is not yet sellable)"
        end

        consumptions = []
        taken = ZERO
        holding.investment_lots.fifo.lock.each do |lot|
          break if taken == to_take

          take = [BigDecimal(lot.remaining_quantity.to_s), to_take - taken].min
          lot.update!(remaining_quantity: lot.remaining_quantity - take)
          taken += take
          consumptions << LotConsumption.new(lot: lot, quantity_taken: take)
        end

        # available_quantity was pre-checked >= to_take; lots on the row must
        # sum to available — belt-and-braces assertion of that invariant.
        if taken != to_take
          raise InsufficientQuantity,
                "lots only cover #{taken} of the requested #{to_take} — " \
                "holding/lot inconsistency for holding #{holding.id}"
        end

        # A sell removes shares from the book: quantity AND available_quantity
        # both drop by `taken` (t1_quantity untouched — settling lots stay
        # settling). average_cost_price updates belong to fill ingestion.
        holding.quantity -= taken
        holding.update!(quantity: holding.quantity, available_quantity: available - taken)
        consumptions.freeze
      end
    end
  end
end
