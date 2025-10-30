# frozen_string_literal: true

class PaperOrder < ApplicationRecord
  STATUSES = {
    pending: 'pending',
    executed: 'executed',
    rejected: 'rejected',
    cancelled: 'cancelled'
  }.freeze

  belongs_to :instrument

  validates :order_no, :security_id, :segment, :transaction_type, :quantity, presence: true
  validates :status, inclusion: { in: STATUSES.values }

  def executed?
    status == STATUSES[:executed]
  end
end
