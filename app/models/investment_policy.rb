# frozen_string_literal: true

# A versioned investment mandate: strategic allocation + constraints
# (TDD §3, §5). One active policy per portfolio — enforced at the DB level by
# the partial unique index idx_investment_policies_one_active_per_portfolio.
class InvestmentPolicy < ApplicationRecord
  STATUSES = %w[draft active retired].freeze

  belongs_to :investment_portfolio
  # class_name is REQUIRED: Rails' inflector singularizes "sleeves" to
  # "sleefe" (the wife/wives rule), so plain `has_many :allocation_sleeves`
  # would look for a class named AllocationSleefe.
  has_many :allocation_sleeves, class_name: "AllocationSleeve",
                                dependent: :destroy, inverse_of: :investment_policy

  validates :mandate_version, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :rebalance_band_min_pct,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :rebalance_band_max_pct,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :band_ordering
  # Sleeve weights must sum to exactly 100 for the policy to be activatable
  # (TDD §5.2 / §16 A1.2 — same rule as the config loader).
  validate :sleeves_sum_to_exactly_100, if: :active?

  def active?
    status == 'active'
  end

  def sleeves_sum_to_exactly_100?
    sum = allocation_sleeves.sum(&:target_weight_pct)
    sum == 100
  end

  def equity_band
    [rebalance_band_min_pct, rebalance_band_max_pct]
  end

  private

  def band_ordering
    return if rebalance_band_min_pct.nil? || rebalance_band_max_pct.nil?
    return if rebalance_band_min_pct < rebalance_band_max_pct

    errors.add(:rebalance_band_min_pct, 'must be strictly below rebalance_band_max_pct')
  end

  def sleeves_sum_to_exactly_100
    return if sleeves_sum_to_exactly_100?

    sum = allocation_sleeves.sum(&:target_weight_pct)
    errors.add(:base, "allocation sleeves must sum to exactly 100 (got #{sum})")
  end
end
