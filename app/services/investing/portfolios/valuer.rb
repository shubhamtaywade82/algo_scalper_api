# frozen_string_literal: true

require "bigdecimal"

module Investing
  module Portfolios
    # Deterministic, pure-read valuation (TDD §6.2). The result plugs straight
    # into Investing::Allocation::Calculator, which consumes total_value,
    # cash_value and sleeve_values.
    #
    # Rules (§6.2):
    #   * a holding with no caller-supplied price uses its stored last_price
    #     (stale-tolerant — long-horizon domain);
    #   * an empty portfolio values to cash_balance;
    #   * weights are computed against total_value (cash counts as its own
    #     sleeve, §7.1 rule 2);
    #   * rounding to 2dp happens only at the struct boundary, never
    #     mid-computation.
    class Valuer
      ZERO = BigDecimal("0")
      HUNDRED = BigDecimal("100")

      # @param portfolio [InvestmentPortfolio]
      # @param prices [Hash{Integer=>BigDecimal}, nil] instrument_id => price;
      #        nil means "use every holding's stored last_price" (hermetic tests)
      # @return [Investing::Portfolios::Valuation]
      def valuation(portfolio, prices: nil)
        price_map = Hash(prices).transform_values { |v| BigDecimal(v.to_s) }

        holding_values = {}
        cost_basis = ZERO
        sleeve_values = Hash.new { |h, k| h[k] = ZERO }

        portfolio.investment_holdings.each do |holding|
          price = price_map.fetch(holding.instrument_id) { BigDecimal(holding.last_price.to_s) }
          value = holding.quantity * price
          holding_values[holding.id] = value
          cost_basis += holding.quantity * BigDecimal(holding.average_cost_price.to_s)
          sleeve_values[holding.sleeve_key] += value
        end

        cash_value = BigDecimal(portfolio.cash_balance.to_s)
        invested_value = holding_values.values.sum(ZERO)
        total_value = invested_value + cash_value

        Valuation.new(
          total_value: rounded(total_value),
          cash_value: rounded(cash_value),
          invested_value: rounded(invested_value),
          cost_basis: rounded(cost_basis),
          sleeve_values: sleeve_values.transform_values { |v| rounded(v) },
          sleeve_weights: sleeve_weights(sleeve_values, total_value, portfolio),
          holding_values: holding_values.transform_values { |v| rounded(v) }
        ).freeze
      end

      private

      # Actual weights at the struct boundary: one entry per sleeve that holds
      # value, plus a synthetic `cash` row whenever cash is invested-or-not
      # but non-zero (§7.1 rule 2: uninvested money shows as cash overweight).
      def sleeve_weights(sleeve_values, total_value, portfolio)
        weights = sleeve_values.transform_values { |v| pct(v, total_value) }
        cash_pct = pct(portfolio.cash_balance.to_d, total_value)
        weights["cash"] = cash_pct if cash_pct.positive?
        weights
      end

      def pct(value, total)
        return ZERO if total.zero?

        ((value * HUNDRED) / total).round(2, :half_up)
      end

      def rounded(value)
        value.round(2, :half_up)
      end
    end

    # Immutable valuation result (TDD §6.2 struct + §7.1 consumption shape).
    class Valuation
      attr_reader :total_value, :cash_value, :invested_value, :cost_basis,
                  :unrealized_pnl, :sleeve_values, :sleeve_weights, :holding_values

      def initialize(total_value:, cash_value:, invested_value:, cost_basis:,
                     sleeve_values:, sleeve_weights:, holding_values:)
        @total_value = total_value
        @cash_value = cash_value
        @invested_value = invested_value
        @cost_basis = cost_basis
        @unrealized_pnl = invested_value - cost_basis
        @sleeve_values = sleeve_values.freeze
        @sleeve_weights = sleeve_weights.freeze
        @holding_values = holding_values.freeze
      end
    end
  end
end
