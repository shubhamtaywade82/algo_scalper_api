# frozen_string_literal: true

require "bigdecimal"

module Investing
  module Portfolios
    # Creates a portfolio with its initial ACTIVE policy materialized from a
    # mandate in config/investing.yml (TDD §6.1).
    #
    # Runs in one transaction: portfolio + policy (with all sleeves) + opening
    # deposit transaction + audit event. Raises Investing::ValidationError —
    # never bare StandardError — on duplicate name, unknown mandate, live-mode
    # gate closed, or negative cash.
    class Creator
      ZERO = BigDecimal("0")

      # @param config [Investing::Config, nil] injectable instance for tests;
      #        lazily resolved via Investing::Config.fetch in production
      def initialize(config: nil)
        @config = config
      end

      # @param name [String] unique portfolio name
      # @param mode [Symbol, String] :paper | :live (paper only until Phase 4)
      # @param mandate [String] key into Investing::Config.mandates
      # @param initial_cash [Numeric, String] BigDecimal-coerced, >= 0
      # @return [InvestmentPortfolio] persisted, with active policy + sleeves
      # @raise [Investing::ValidationError]
      def call(name:, mandate:, initial_cash:, mode: :paper)
        mode_s = mode.to_s
        cash = BigDecimal(initial_cash.to_s)
        mandate_name = mandate.to_s

        raise ValidationError, "initial_cash must be >= 0 (got #{cash})" if cash.negative?
        if mode_s == "live" && ENV["INVESTING_LIVE_CONFIRMED"] != "yes"
          raise ValidationError,
                "live portfolios require INVESTING_LIVE_CONFIRMED=yes (Phase 4 gate, TDD §19.2)"
        end
        raise ValidationError, "portfolio name already taken: #{name}" if
          InvestmentPortfolio.exists?(name: name.to_s)

        fetch_mandate(mandate_name)

        portfolio = nil
        ActiveRecord::Base.transaction do
          portfolio = InvestmentPortfolio.create!(
            name: name.to_s,
            mode: mode_s,
            base_currency: "INR",
            cash_balance: cash,
            invested_amount: ZERO,
            meta: { "mandate" => mandate_name }
          )
          # Build policy + sleeves in memory, save once: the active-policy
          # validation (sleeves sum to exactly 100, §5.2) sees the sleeves.
          policy = portfolio.investment_policies.new(
            mandate_version: mandate_name,
            status: "active",
            constraints: config_instance.constraints_for(mandate_name),
            rebalance_band_min_pct: config_instance.equity_band_for(mandate_name)[0],
            rebalance_band_max_pct: config_instance.equity_band_for(mandate_name)[1],
            effective_from: business_date
          )
          config_instance.sleeves_for(mandate_name).each_with_index do |sleeve, i|
            policy.allocation_sleeves.build(
              sleeve_key: sleeve.fetch("key"),
              sleeve_name: sleeve.fetch("name"),
              asset_class: sleeve.fetch("asset_class"),
              target_weight_pct: sleeve.fetch("target_weight_pct"),
              display_order: i
            )
          end
          policy.save!
          if cash.positive?
            portfolio.investment_transactions.create!(
              txn_type: "deposit", amount: cash, quantity_delta: 0,
              meta: { "note" => "opening deposit" }
            )
          end
          AuditLog.create!(
            event_type: "investing_portfolio_created",
            actor: "system",
            metadata: {
              portfolio_id: portfolio.id, name: portfolio.name,
              mode: mode_s, mandate: mandate_name, initial_cash: cash.to_s
            }
          )
        end
        portfolio
      end

      private

      def fetch_mandate(name)
        cfg = config_instance
        # Distinguish "bad caller input" (typed ValidationError) from
        # "config never loaded" (Config::Error — a boot bug that must
        # stay loud, not be masked as a validation failure).
        unless cfg.mandates.key?(name.to_s)
          raise ValidationError, "unknown investing mandate: #{name}"
        end

        cfg.mandate(name)
      end

      def config_instance
        @config || Investing::Config.fetch
      end

      def business_date
        Time.now.in_time_zone("Asia/Kolkata").to_date
      end
    end
  end
end
