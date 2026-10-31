# frozen_string_literal: true

# One acquisition batch of an instrument: FIFO cost-basis accounting
# (TDD §3.2, §4, §6.5). A sell consumes remaining_quantity oldest-first,
# ordered by (acquired_on, id) — deterministic, never DB default order.
# lot_source: order (bought via Investing order), transfer (imported from
# broker holdings, Phase 3), corporate_action (bonus/split).
class InvestmentLot < ApplicationRecord
  SOURCES = %w[order transfer corporate_action].freeze

  belongs_to :investment_holding, inverse_of: :investment_lots
  belongs_to :investment_order, optional: true

  validates :quantity, numericality: { greater_than: 0 }
  validates :remaining_quantity,
            numericality: { greater_than_or_equal_to: 0 }
  validates :buy_price, numericality: { greater_than_or_equal_to: 0 }
  validates :acquired_on, presence: true
  validates :lot_source, inclusion: { in: SOURCES }

  validate :remaining_cannot_exceed_quantity

  scope :fifo, -> { where("remaining_quantity > 0").order(acquired_on: :asc, id: :asc) }

  def fully_consumed?
    remaining_quantity.zero?
  end

  private

  def remaining_cannot_exceed_quantity
    return if remaining_quantity.nil? || quantity.nil?
    return if remaining_quantity <= quantity

    errors.add(:remaining_quantity,
               "cannot exceed lot quantity (#{remaining_quantity} > #{quantity})")
  end
end
