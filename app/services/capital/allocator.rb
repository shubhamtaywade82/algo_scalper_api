# frozen_string_literal: true

require "bigdecimal"

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
      def qty_for(index_cfg:, entry_price:, derivative_lot_size:)
        capital_available = available_cash
        return 0 if capital_available.zero?

        return 0 if entry_price.to_f <= 0

        # Get deployment policy based on account size
        policy = deployment_policy(capital_available.to_f)

        # Use policy values, but allow config override for allocation %
        effective_alloc_pct = index_cfg[:capital_alloc_pct] || policy[:alloc_pct]
        effective_risk_pct = policy[:risk_per_trade_pct]

        allocation = capital_available * effective_alloc_pct
        # Always use derivative lot size - no fallback to index config
        lot_size = derivative_lot_size.to_i
        Rails.logger.debug("[Capital] Using derivative lot_size: #{lot_size}")
        return 0 if lot_size <= 0

        # Safety check: Can we afford at least 1 lot?
        min_lot_cost = entry_price.to_f * lot_size
        if capital_available < min_lot_cost
          Rails.logger.warn("[Capital] Insufficient capital for minimum lot: Available ₹#{capital_available}, Required ₹#{min_lot_cost}")
          return 0
        end

        risk_capital = capital_available * effective_risk_pct

        max_by_allocation = (allocation / (entry_price.to_f * lot_size)).floor * lot_size
        max_by_risk = (risk_capital / (entry_price.to_f * 0.30)).floor * lot_size

        quantity = [ max_by_allocation, max_by_risk ].min
        final_quantity = [ [ quantity, lot_size ].max, lot_size * 100 ].min

        # Safety check: Ensure final buy value doesn't exceed available capital
        final_buy_value = entry_price.to_f * final_quantity
        if final_buy_value > capital_available
          Rails.logger.warn("[Capital] Final buy value exceeds available capital: Buy ₹#{final_buy_value}, Available ₹#{capital_available}")
          # Reduce quantity to fit within available capital
          max_affordable_lots = (capital_available / (entry_price.to_f * lot_size)).floor
          final_quantity = max_affordable_lots * lot_size
          final_quantity = [ final_quantity, lot_size ].max # Ensure at least 1 lot
          Rails.logger.info("[Capital] Adjusted quantity to fit available capital: #{final_quantity}")
        end

        Rails.logger.info("[Capital] Calculation breakdown:")
        Rails.logger.info("  - Available capital: ₹#{capital_available}")
        Rails.logger.info("  - Capital band: #{policy[:upto] == Float::INFINITY ? 'Large' : "Up to ₹#{policy[:upto]}"}")
        Rails.logger.info("  - Effective allocation %: #{effective_alloc_pct * 100}%")
        Rails.logger.info("  - Allocation amount: ₹#{allocation}")
        Rails.logger.info("  - Effective risk %: #{effective_risk_pct * 100}%")
        Rails.logger.info("  - Risk capital amount: ₹#{risk_capital}")
        Rails.logger.info("  - Entry price: ₹#{entry_price}")
        Rails.logger.info("  - Lot size: #{lot_size}")
        Rails.logger.info("  - Max by allocation: #{max_by_allocation}")
        Rails.logger.info("  - Max by risk: #{max_by_risk}")
        Rails.logger.info("  - Final quantity: #{final_quantity}")
        Rails.logger.info("  - Total buy value: ₹#{entry_price * final_quantity}")

        final_quantity
      rescue StandardError => e
        Rails.logger.error("Capital::Allocator failed: #{e.class} - #{e.message}")
        0
      end

      # Capital-aware deployment policy based on account size
      def deployment_policy(balance)
        band = CAPITAL_BANDS.find { |b| balance <= b[:upto] } || CAPITAL_BANDS.last
        # Allow env overrides (optional)
        alloc = ENV["ALLOC_PCT"]&.to_f || band[:alloc_pct]
        r_pt  = ENV["RISK_PER_TRADE_PCT"]&.to_f || band[:risk_per_trade_pct]
        d_ml  = ENV["DAILY_MAX_LOSS_PCT"]&.to_f || band[:daily_max_loss_pct]

        {
          upto: band[:upto],
          alloc_pct: alloc,
          risk_per_trade_pct: r_pt,
          daily_max_loss_pct: d_ml
        }
      end

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
