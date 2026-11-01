# frozen_string_literal: true

module Investing
  module Portfolios
    # Persists a daily valuation snapshot (TDD §6.4). Idempotent per
    # (portfolio, as_of_date): re-running the same date overwrites the row
    # (unique-index upsert). The ONLY writer of investment_snapshots.
    class Snapshotter
      # @param valuer [Investing::Portfolios::Valuer] injectable for tests
      def initialize(valuer: Valuer.new)
        @valuer = valuer
      end

      # @param portfolio [InvestmentPortfolio]
      # @param date [Date, nil] defaults to the business date (IST)
      # @return [InvestmentSnapshot] upserted by [portfolio, as_of_date]
      def snapshot!(portfolio, date: nil)
        as_of = date || business_date
        valuation = @valuer.valuation(portfolio)

        snapshot = InvestmentSnapshot.find_or_initialize_by(
          investment_portfolio_id: portfolio.id, as_of_date: as_of
        )
        snapshot.update!(
          total_value: valuation.total_value,
          cash_balance: valuation.cash_value,
          invested_value: valuation.invested_value,
          sleeve_weights: valuation.sleeve_weights.transform_keys(&:to_s)
        )
        snapshot
      end

      private

      def business_date
        Time.now.in_time_zone("Asia/Kolkata").to_date
      end
    end
  end
end
