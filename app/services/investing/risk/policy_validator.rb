# frozen_string_literal: true

require "bigdecimal"

module Investing
  module Risk
    # Pre-trade policy gate (TDD §9.1). Deterministic, table-driven, pure —
    # projects the post-trade portfolio state and checks every hard constraint.
    #
    # Duck-typed inputs so the spike is testable before every model exists:
    #   portfolio_state: responds to cash_balance, holdings (each responds to
    #                    instrument_id, sleeve_key, asset_class, value,
    #                    is_illiquid, sector), orders_today (Integer)
    #   order:           responds to side (:buy/:sell), instrument_id,
    #                    sleeve_key, asset_class, sector, is_illiquid, value,
    #                    quantity, available_quantity
    class PolicyValidator
      # Rule identifiers (TDD §9.1 table).
      RULES = %i[
        max_single_stock max_sector max_illiquid equity_band
        max_order_value max_orders_per_day insufficient_available_qty
      ].freeze

      DEFAULT_CONSTRAINTS = {
        "max_single_stock_pct" => BigDecimal("2.5"),
        "max_sector_pct" => BigDecimal("12"),
        "max_illiquid_pct" => BigDecimal("25"),
        "equity_band_pct" => [BigDecimal("50"), BigDecimal("60")]
      }.freeze
      DEFAULT_EXECUTION = {
        "max_order_value_inr" => BigDecimal("500_000"),
        "max_orders_per_day" => 12
      }.freeze

      Violation = Struct.new(:rule, :message, :actual, :limit, keyword_init: true) do
        def to_h
          { rule: rule, message: message, actual: actual&.to_s("F"), limit: limit&.to_s("F") }
        end
      end

      CheckResult = Struct.new(:violations, keyword_init: true) do
        def ok?
          violations.empty?
        end
      end

      # @param constraints [Hash] policy constraints (DEFAULT_CONSTRAINTS shape)
      # @param execution [Hash] execution limits (DEFAULT_EXECUTION shape)
      def initialize(constraints: DEFAULT_CONSTRAINTS, execution: DEFAULT_EXECUTION)
        @constraints = DEFAULT_CONSTRAINTS.merge(constraints || {})
        @execution = DEFAULT_EXECUTION.merge(execution || {})
      end

      # @return [Investing::Risk::PolicyValidator::CheckResult]
      def check(portfolio_state:, order:)
        violations = [
          check_max_single_stock(portfolio_state, order),
          check_max_sector(portfolio_state, order),
          check_max_illiquid(portfolio_state, order),
          check_equity_band(portfolio_state, order),
          check_max_order_value(order),
          check_max_orders_per_day(portfolio_state),
          check_available_quantity(order)
        ].compact

        CheckResult.new(violations: violations)
      end

      private

      def total_value(portfolio_state)
        portfolio_state.holdings.sum(&:value) + BigDecimal(portfolio_state.cash_balance.to_s)
      end

      # Post-trade denominators: buys add the order value to both numerator and
      # denominator; sells remove from both. Sells of the same instrument reduce
      # concentration, but we still check (harmless, and catches data bugs).
      def projected_weight(portfolio_state, order, selector)
        order_value = BigDecimal(order.value.to_s)
        current = portfolio_state.holdings
                                 .select { |h| selector.call(h) }
                                 .sum(&:value)
        post_holding =
          case order.side.to_sym
          when :buy  then current + order_value
          when :sell then current - order_value
          else raise ArgumentError, "side must be :buy or :sell"
          end
        total = total_value(portfolio_state)
        post_total =
          case order.side.to_sym
          when :buy  then total + order_value
          when :sell then total - order_value
          end
        return BigDecimal("0") if post_total.zero?

        ((post_holding * BigDecimal("100")) / post_total).round(4, :half_up)
      end

      def check_max_single_stock(portfolio_state, order)
        limit = to_d(@constraints["max_single_stock_pct"])
        weight = projected_weight(portfolio_state, order, ->(h) { h.instrument_id == order.instrument_id })
        return if weight <= limit

        Violation.new(rule: :max_single_stock,
                      message: "post-trade single-stock weight #{weight}% exceeds #{limit}%",
                      actual: weight, limit: limit)
      end

      def check_max_sector(portfolio_state, order)
        limit = to_d(@constraints["max_sector_pct"])
        sector = order.sector
        weight = projected_weight(portfolio_state, order, ->(h) { h.sector == sector })
        return if weight <= limit

        Violation.new(rule: :max_sector,
                      message: "post-trade sector #{sector} weight #{weight}% exceeds #{limit}%",
                      actual: weight, limit: limit)
      end

      def check_max_illiquid(portfolio_state, order)
        limit = to_d(@constraints["max_illiquid_pct"])
        illiquid = projected_weight(portfolio_state, order, ->(h) { h.is_illiquid == true })
        return if illiquid <= limit

        Violation.new(rule: :max_illiquid,
                      message: "post-trade illiquid weight #{illiquid}% exceeds #{limit}%",
                      actual: illiquid, limit: limit)
      end

      # Symmetric guard (TDD §9.1): equity buys must not push the equity weight
      # above the band max; equity sells must not push it below the band min.
      def check_equity_band(portfolio_state, order)
        band = @constraints["equity_band_pct"] || DEFAULT_CONSTRAINTS["equity_band_pct"]
        lo = to_d(band[0])
        hi = to_d(band[1])
        return unless order.asset_class == "equity"

        weight = projected_weight(portfolio_state, order, ->(h) { h.asset_class == "equity" })
        if order.side.to_sym == :buy && weight > hi
          return Violation.new(rule: :equity_band,
                               message: "post-trade equity weight #{weight}% above band max #{hi}%",
                               actual: weight, limit: hi)
        end
        return unless order.side.to_sym == :sell && weight < lo

        Violation.new(rule: :equity_band,
                      message: "post-trade equity weight #{weight}% below band min #{lo}%",
                      actual: weight, limit: lo)
      end

      def check_max_order_value(order)
        limit = to_d(@execution["max_order_value_inr"])
        value = BigDecimal(order.value.to_s)
        return if value <= limit

        Violation.new(rule: :max_order_value,
                      message: "order value #{value} exceeds #{limit}",
                      actual: value, limit: limit)
      end

      def check_max_orders_per_day(portfolio_state)
        limit = @execution["max_orders_per_day"].to_i
        count = portfolio_state.orders_today.to_i
        return if count < limit

        Violation.new(rule: :max_orders_per_day,
                      message: "#{count} orders already placed today (limit #{limit})",
                      actual: count, limit: limit)
      end

      def check_available_quantity(order)
        return unless order.side.to_sym == :sell

        requested = BigDecimal(order.quantity.to_s)
        available = BigDecimal(order.available_quantity.to_s)
        return if requested <= available

        Violation.new(rule: :insufficient_available_qty,
                      message: "sell of #{requested} exceeds available #{available} (T+1 excluded)",
                      actual: requested, limit: available)
      end

      def to_d(value)
        BigDecimal(value.to_s)
      end
    end
  end
end
