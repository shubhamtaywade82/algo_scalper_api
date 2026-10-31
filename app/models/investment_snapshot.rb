# frozen_string_literal: true

# Daily valuation point for an InvestmentPortfolio (TDD §3.2, §6.4).
# Uniquely keyed by (portfolio, as_of_date) — re-running a day overwrites,
# so charting queries are stable and re-runs are idempotent.
# The ONLY writer is Investing::Portfolios::Snapshotter.
class InvestmentSnapshot < ApplicationRecord
  belongs_to :investment_portfolio

  validates :as_of_date, presence: true
  validates :as_of_date,
            uniqueness: { scope: :investment_portfolio_id }
  validates :total_value, :cash_balance, :invested_value,
            numericality: { greater_than_or_equal_to: 0 }

  # XIRR is optional (Phase 5 computes it once enough history exists).
  validates :xirr, numericality: true, allow_nil: true
end
