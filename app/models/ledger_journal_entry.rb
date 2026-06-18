# frozen_string_literal: true

class LedgerJournalEntry < ApplicationRecord
  belongs_to :position_tracker, optional: true
  has_many :ledger_postings, dependent: :destroy

  validates :idempotency_key, presence: true, uniqueness: { case_sensitive: true }
  validates :event_type, presence: true
  validates :mode, presence: true
  validates :trading_date, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_mode, ->(mode) { where(mode: mode.to_s) }
end
