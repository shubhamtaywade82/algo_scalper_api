# frozen_string_literal: true

# Append-only cash/share movement ledger for an InvestmentPortfolio
# (TDD §3.2, §4). Everything that changes cash_balance or quantity must
# produce exactly one row: buy | sell | dividend | deposit | withdrawal |
# charge | corporate_action.
class InvestmentTransaction < ApplicationRecord
  TXN_TYPES = %w[buy sell dividend deposit withdrawal charge corporate_action].freeze

  belongs_to :investment_portfolio
  belongs_to :investment_order, optional: true

  validates :txn_type, inclusion: { in: TXN_TYPES }
  validates :amount, presence: true, numericality: true
  # Signed share movement: +qty on buy, -qty on sell, 0 for cash-only rows.
  validates :quantity_delta, numericality: true
end
