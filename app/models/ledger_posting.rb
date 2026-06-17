# frozen_string_literal: true

class LedgerPosting < ApplicationRecord
  belongs_to :ledger_journal_entry
  belongs_to :ledger_account

  validates :debit, numericality: { greater_than_or_equal_to: 0 }
  validates :credit, numericality: { greater_than_or_equal_to: 0 }
  validate :debit_or_credit_present

  private

  def debit_or_credit_present
    return if debit.to_d.positive? ^ credit.to_d.positive?

    errors.add(:base, 'posting must have exactly one of debit or credit positive')
  end
end
