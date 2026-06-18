# frozen_string_literal: true

class LedgerAccount < ApplicationRecord
  ACCOUNT_TYPES = %w[asset expense income equity].freeze

  has_many :ledger_postings, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: { case_sensitive: true }
  validates :name, presence: true
  validates :account_type, presence: true, inclusion: { in: ACCOUNT_TYPES }
  validates :currency, presence: true

  scope :by_code, ->(code) { where(code: code.to_s) }

  def self.fetch!(code)
    find_by!(code: code.to_s)
  end

  def apply_posting!(debit:, credit:)
    delta = debit_amount_delta(debit: debit, credit: credit)
    update!(balance_cache: balance_cache.to_d + delta)
  end

  private

  def debit_amount_delta(debit:, credit:)
    debit_bd = BigDecimal(debit.to_s)
    credit_bd = BigDecimal(credit.to_s)

    case account_type
    when 'asset', 'expense'
      debit_bd - credit_bd
    when 'income', 'equity'
      credit_bd - debit_bd
    else
      debit_bd - credit_bd
    end
  end
end
