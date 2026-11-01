# frozen_string_literal: true

# One strategic allocation bucket inside an InvestmentPolicy (TDD §3, §5).
# Example: large_cap_core @ 25% equity.
class AllocationSleeve < ApplicationRecord
  # infra = real-assets class, deliberately NOT equity (TDD §5 asset-class note)
  ASSET_CLASSES = %w[equity debt reit invit gold cash infra].freeze

  belongs_to :investment_policy, inverse_of: :allocation_sleeves

  validates :sleeve_key, presence: true,
                         uniqueness: { scope: :investment_policy_id }
  validates :sleeve_name, presence: true
  validates :asset_class, inclusion: { in: ASSET_CLASSES }
  validates :target_weight_pct,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :display_order, numericality: { only_integer: true,
                                            greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:display_order, :id) }
end
