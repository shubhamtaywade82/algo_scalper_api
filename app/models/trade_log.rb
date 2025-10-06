# frozen_string_literal: true

class TradeLog < ApplicationRecord
  enum :direction, { long: 0, short: 1 }, _prefix: true
  enum :status, { pending: 0, open: 1, closed: 2, failed: 3 }, _prefix: true

  scope :for_strategy, ->(strategy) { where(strategy: strategy) }
  scope :active, -> { where(status: %i[pending open]) }

  before_validation :ensure_metadata

  validates :strategy, presence: true
  validates :segment, presence: true
  validates :security_id, presence: true
  validates :direction, presence: true
  validates :status, presence: true
  validates :quantity, numericality: { greater_than: 0 }

  def mark_open!(order_id:, entry_price: nil)
    update!(
      status: :open,
      order_id: order_id,
      entry_price: entry_price,
      placed_at: Time.current
    )
  end

  def mark_failed!(error_message)
    update!(
      status: :failed,
      metadata: metadata.to_h.merge(error: error_message, failed_at: Time.current)
    )
  end

  def close!(exit_order_id:, exit_price: nil)
    update!(
      status: :closed,
      exit_order_id: exit_order_id,
      exit_price: exit_price,
      closed_at: Time.current
    )
  end

  private

  def ensure_metadata
    self.metadata = metadata.presence || {}
  end
end
