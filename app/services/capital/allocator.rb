# frozen_string_literal: true

require 'bigdecimal'
require_relative '../concerns/broker_fee_calculator'

module Capital
  class Allocator
    # Capital-aware deployment policy based on account size
    # Bands are inclusive upper-bounds. Smaller accounts get higher allocation % but lower risk %
    CAPITAL_BANDS = [
      { upto: 75_000, alloc_pct: 0.30, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.050 }, # small a/c (≈ ₹50k)
      { upto: 150_000, alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 }, # ≈ ₹1L
      { upto: 300_000, alloc_pct: 0.20, risk_per_trade_pct: 0.030, daily_max_loss_pct: 0.060 }, # ≈ ₹2–3L
      { upto: Float::INFINITY, alloc_pct: 0.20, risk_per_trade_pct: 0.025, daily_max_loss_pct: 0.050 }
    ].freeze

    class << self
      def qty_for(index_cfg:, entry_price:, derivative_lot_size:, scale_multiplier: 1)
        multiplier = normalize_multiplier(scale_multiplier)
        capital_available = available_cash

        return 0 unless valid_for_allocation?(index_cfg, entry_price, derivative_lot_size, capital_available)

        # Check if rupee-based position sizing is enabled
        if rupee_based_sizing_enabled?
          return calculate_rupee_based_quantity(
            entry_price: entry_price,
            derivative_lot_size: derivative_lot_size,
            capital_available: capital_available,
            multiplier: multiplier
          )
        end

        calculate_and_apply_quantity(
          index_cfg: index_cfg,
          entry_price: entry_price,
          derivative_lot_size: derivative_lot_size,
          capital_available: capital_available,
          multiplier: multiplier
        )
      rescue StandardError => e
        log_allocation_error(index_cfg, e)
        0
      end

      def deployment_policy(balance)
        band = find_capital_band(balance)
        build_policy_with_overrides(band)
      end

      def available_cash
        return paper_trading_balance if paper_trading_enabled?

        fetch_live_trading_balance
      rescue StandardError => e
        log_balance_fetch_error(e)
        BigDecimal(0)
      end

      def paper_trading_enabled?
        AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
      end

      def paper_trading_balance
        balance = AlgoConfig.fetch.dig(:paper_trading, :balance) || 100_000
        BigDecimal(balance.to_s)
      end

      private

      def normalize_multiplier(scale_multiplier)
        [scale_multiplier.to_i, 1].max
      end

      def valid_for_allocation?(index_cfg, entry_price, derivative_lot_size, capital_available)
        return log_and_return_false("[Capital] Available capital is zero for #{index_cfg[:key]}") if capital_available.zero?
        return log_and_return_false("[Capital] Invalid entry price for #{index_cfg[:key]}: #{entry_price}") if entry_price.to_f <= 0

        lot_size = derivative_lot_size.to_i
        return log_and_return_false("[Capital] Invalid lot size for #{index_cfg[:key]}: #{lot_size}") if lot_size <= 0

        unless can_afford_minimum_lot?(
          entry_price, lot_size, capital_available
        )
          return log_insufficient_capital(index_cfg, entry_price, lot_size,
                                          capital_available)
        end

        true
      end

      def can_afford_minimum_lot?(entry_price, lot_size, capital_available)
        min_lot_cost = entry_price.to_f * lot_size
        capital_available >= min_lot_cost
      end

      def log_insufficient_capital(index_cfg, entry_price, lot_size, capital_available)
        min_lot_cost = entry_price.to_f * lot_size
        Rails.logger.warn("[Capital] Insufficient capital for minimum lot for #{index_cfg[:key]}: Available ₹#{capital_available}, Required ₹#{min_lot_cost} (price: ₹#{entry_price}, lot_size: #{lot_size})")
        false
      end

      def log_and_return_false(message)
        Rails.logger.warn(message)
        false
      end

      def calculate_and_apply_quantity(index_cfg:, entry_price:, derivative_lot_size:, capital_available:, multiplier:)
        @index_key = index_cfg[:key] || 'UNKNOWN'
        capital_available_f = capital_available.to_f
        entry_price_f = entry_price.to_f
        lot_size = derivative_lot_size.to_i

        policy = deployment_policy(capital_available_f)
        effective_alloc_pct = index_cfg[:capital_alloc_pct] || policy[:alloc_pct]
        effective_risk_pct = policy[:risk_per_trade_pct]

        quantity = calculate_quantity_by_constraints(
          capital_available_f: capital_available_f,
          entry_price_f: entry_price_f,
          lot_size: lot_size,
          effective_alloc_pct: effective_alloc_pct,
          effective_risk_pct: effective_risk_pct,
          multiplier: multiplier
        )

        final_quantity = apply_quantity_safety_checks(
          quantity: quantity,
          entry_price_f: entry_price_f,
          lot_size: lot_size,
          capital_available_f: capital_available_f
        )

        log_allocation_breakdown(
          capital_available: capital_available,
          policy: policy,
          effective_alloc_pct: effective_alloc_pct,
          effective_risk_pct: effective_risk_pct,
          multiplier: multiplier,
          entry_price_f: entry_price_f,
          lot_size: lot_size,
          final_quantity: final_quantity
        )

        final_quantity
      end

      def calculate_quantity_by_constraints(capital_available_f:, entry_price_f:, lot_size:, effective_alloc_pct:,
                                            effective_risk_pct:, multiplier:)
        max_by_allocation = calculate_max_by_allocation(capital_available_f, entry_price_f, lot_size,
                                                        effective_alloc_pct, multiplier)
        max_by_risk = calculate_max_by_risk(capital_available_f, entry_price_f, lot_size, effective_risk_pct,
                                            multiplier)

        [max_by_allocation, max_by_risk].min
      end

      def calculate_max_by_allocation(capital_available_f, entry_price_f, lot_size, effective_alloc_pct, multiplier)
        allocation = capital_available_f * effective_alloc_pct
        scaled_allocation = [allocation * multiplier, capital_available_f].min
        cost_per_lot = entry_price_f * lot_size

        (scaled_allocation / cost_per_lot).floor * lot_size
      end

      def calculate_max_by_risk(capital_available_f, entry_price_f, lot_size, effective_risk_pct, multiplier)
        risk_capital = capital_available_f * effective_risk_pct
        risk_capital_scaled = [risk_capital * multiplier, capital_available_f].min
        stop_loss_per_share = entry_price_f * 0.30

        (risk_capital_scaled / stop_loss_per_share).floor * lot_size
      end

      def apply_quantity_safety_checks(quantity:, entry_price_f:, lot_size:, capital_available_f:)
        final_quantity = enforce_lot_size_constraints(quantity, lot_size)
        adjust_if_exceeds_capital(final_quantity, entry_price_f, lot_size, capital_available_f)
      end

      def enforce_lot_size_constraints(quantity, lot_size)
        [[quantity, lot_size].max, lot_size * 100].min
      end

      def adjust_if_exceeds_capital(final_quantity, entry_price_f, lot_size, capital_available_f)
        final_buy_value = entry_price_f * final_quantity
        return final_quantity if final_buy_value <= capital_available_f

        reduce_to_affordable_quantity(entry_price_f, lot_size, capital_available_f)
      end

      def reduce_to_affordable_quantity(entry_price_f, lot_size, capital_available_f)
        cost_per_lot = entry_price_f * lot_size
        max_affordable_lots = (capital_available_f / cost_per_lot).floor
        final_quantity = max_affordable_lots * lot_size

        [final_quantity, lot_size].max
      end

      def find_capital_band(balance)
        CAPITAL_BANDS.find { |b| balance <= b[:upto] } || CAPITAL_BANDS.last
      end

      def build_policy_with_overrides(band)
        {
          upto: band[:upto],
          alloc_pct: allocation_percentage_with_override(band),
          risk_per_trade_pct: risk_per_trade_with_override(band),
          daily_max_loss_pct: daily_max_loss_with_override(band)
        }
      end

      def allocation_percentage_with_override(band)
        # Prefer algo.yml config, ENV as fallback for testing
        band[:alloc_pct] || ENV['ALLOC_PCT']&.to_f
      end

      def risk_per_trade_with_override(band)
        # Prefer algo.yml config, ENV as fallback for testing
        band[:risk_per_trade_pct] || ENV['RISK_PER_TRADE_PCT']&.to_f
      end

      def daily_max_loss_with_override(band)
        # Prefer algo.yml config, ENV as fallback for testing
        band[:daily_max_loss_pct] || ENV['DAILY_MAX_LOSS_PCT']&.to_f
      end

      def fetch_live_trading_balance
        data = DhanHQ::Models::Funds.fetch
        value = data.available_balance

        return handle_missing_balance(data) if value.nil?

        convert_to_bigdecimal(value)
      end

      def handle_missing_balance(data)
        Rails.logger.warn("[Capital] Failed to extract available_balance from funds data: #{data.inspect}")
        BigDecimal(0)
      end

      def convert_to_bigdecimal(value)
        result = value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
        Rails.logger.debug { "[Capital] Available cash: ₹#{result}" }
        result
      end

      def log_balance_fetch_error(error)
        Rails.logger.error("[Capital] Failed to fetch available cash: #{error.class} - #{error.message}")
        Rails.logger.error("[Capital] Backtrace: #{error.backtrace.first(3).join(', ')}")
      end

      def log_allocation_error(index_cfg, error)
        Rails.logger.error("[Capital] Allocator failed for #{index_cfg[:key]}: #{error.class} - #{error.message}")
        Rails.logger.error("[Capital] Backtrace: #{error.backtrace.first(3).join(', ')}")
      end

      def log_allocation_breakdown(capital_available:, entry_price_f:, lot_size:, final_quantity:, policy: nil,
                                   effective_alloc_pct: nil, effective_risk_pct: nil, multiplier: nil)
        capital_available_f = capital_available.to_f
        cost_per_lot = entry_price_f * lot_size
        index_key = @index_key || 'UNKNOWN'

        reason = if final_quantity.zero?
                   'insufficient_capital'
                 elsif final_quantity < lot_size
                   'below_minimum_lot'
                 else
                   'allocated'
                 end

        Rails.logger.info(
          "[Allocator] index:#{index_key} lot_cost:₹#{cost_per_lot.round(2)} " \
          "capital:₹#{capital_available_f.round(2)} qty:#{final_quantity} reason:#{reason}"
        )
      end

      # Rupee-based position sizing: derive quantity from fixed ₹ risk
      # Formula: quantity = floor(risk_rupees / (stop_distance_rupees × lot_size)) × lot_size
      def calculate_rupee_based_quantity(entry_price:, derivative_lot_size:, capital_available:, multiplier:)
        sizing_cfg = position_sizing_config
        return 0 unless sizing_cfg && sizing_cfg[:enabled]

        risk_rupees = BigDecimal((sizing_cfg[:risk_rupees] || 1000).to_s)
        index_key = @index_key || 'UNKNOWN'

        # Deduct broker fees from risk capital (₹40 per trade: entry + exit)
        # This ensures net risk after fees matches the target risk
        broker_fees = BrokerFeeCalculator.fee_per_trade
        net_risk_rupees = risk_rupees - broker_fees

        # Get index-specific stop distance or fallback to global
        index_stop_distances = sizing_cfg[:index_stop_distances] || {}
        stop_distance_rupees = if index_stop_distances[index_key.to_sym] || index_stop_distances[index_key.to_s]
                                 BigDecimal((index_stop_distances[index_key.to_sym] || index_stop_distances[index_key.to_s]).to_s)
                               else
                                 BigDecimal((sizing_cfg[:stop_distance_rupees] || 8).to_s)
                               end
        lot_size = derivative_lot_size.to_i

        return 0 if stop_distance_rupees.zero? || lot_size.zero?
        return 0 if net_risk_rupees <= 0 # Not enough risk capital after fees

        # Calculate risk per lot
        risk_per_lot = stop_distance_rupees * lot_size

        # Calculate max lots based on net risk (after fees)
        max_lots_by_risk = (net_risk_rupees / risk_per_lot).floor

        # Apply multiplier
        max_lots = max_lots_by_risk * multiplier

        # Calculate quantity (must be lot-aligned)
        quantity = max_lots * lot_size

        # Ensure minimum 1 lot
        quantity = [quantity, lot_size].max

        # Check capital constraint
        cost_per_lot = BigDecimal(entry_price.to_s) * lot_size
        max_affordable_lots = (capital_available / cost_per_lot).floor
        max_affordable_quantity = max_affordable_lots * lot_size

        # Take minimum of risk-based and capital-based quantity
        final_quantity = [quantity, max_affordable_quantity].min

        # Ensure at least 1 lot
        final_quantity = [final_quantity, lot_size].max

        # Log breakdown
        Rails.logger.info(
          "[Allocator] RUPEES_BASED index:#{index_key} risk:₹#{risk_rupees} " \
          "fees:₹#{broker_fees} net_risk:₹#{net_risk_rupees} " \
          "stop_dist:₹#{stop_distance_rupees} risk_per_lot:₹#{risk_per_lot} " \
          "max_lots:#{max_lots_by_risk} qty:#{final_quantity} " \
          "buy_value:₹#{(entry_price.to_f * final_quantity).round(2)}"
        )

        final_quantity
      end

      def rupee_based_sizing_enabled?
        sizing_cfg = position_sizing_config
        sizing_cfg && sizing_cfg[:enabled] == true
      end

      def position_sizing_config
        AlgoConfig.fetch[:position_sizing]
      rescue StandardError
        nil
      end
    end
  end
end
