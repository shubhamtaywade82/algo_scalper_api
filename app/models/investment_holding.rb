# frozen_string_literal: true

# One instrument position inside an InvestmentPortfolio (TDD §3.2, §4).
# quantity = available_quantity + t1_quantity; T+1-settled shares live in
# t1_quantity and are NOT sellable (TDD §6.5 / §16 A1.9 T+1 guard).
# Deliberately shares nothing with Trading::PositionTracker (§1.3.4).
class InvestmentHolding < ApplicationRecord
  belongs_to :investment_portfolio
  belongs_to :instrument

  has_many :investment_lots, dependent: :destroy, inverse_of: :investment_holding

  validates :sleeve_key, presence: true
  validates :instrument, uniqueness: { scope: :investment_portfolio_id }
  validates :quantity, :available_quantity, :t1_quantity,
            numericality: { greater_than_or_equal_to: 0 }
  validates :average_cost_price, :last_price,
            numericality: { greater_than_or_equal_to: 0 }

  validate :available_plus_t1_equals_quantity

  # Consistency invariant split across columns:
  #   quantity      = total shares owned (settled + settling)
  #   t1_quantity   = bought today, not yet settled (not sellable)
  #   available     = sellable now = quantity - t1_quantity
  def available_plus_t1_equals_quantity
    return if quantity.nil? || available_quantity.nil? || t1_quantity.nil?
    return if (available_quantity + t1_quantity) == quantity

    errors.add(:available_quantity,
               "must equal quantity - t1_quantity (got #{available_quantity} + #{t1_quantity} != #{quantity})")
  end

  # Market value at the supplied (or last-known) price.
  def value_at(price)
    quantity * BigDecimal(price.to_s)
  end
end
