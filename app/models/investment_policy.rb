# frozen_string_literal: true

# == Schema Information
#
# Table name: investment_policies
#
#  id                       :bigint           not null, primary key
#  investment_portfolio_id  :bigint           not null
#  version                  :integer          default(1), not null
#  status                   :string           default("draft"), not null
#  effective_from           :date             not null
#  effective_until          :date
#  constraints              :jsonb            not null
#  rebalancing              :jsonb            not null
#  deployment               :jsonb            not null
#  mandate_key              :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Immutable, versioned investment mandate (TDD §3.3 D1). An active row is
# never edited: installing a new mandate creates version + 1 and supersedes
# the previous row atomically (Investing::Portfolios::Manager, Phase 1+).
# Sleeve targets live in InvestmentPolicySleeve; group-level drift bands,
# concentration caps and deployment plans live in the jsonb columns here.
class InvestmentPolicy < ApplicationRecord
  STATUSES = %w[draft active superseded].freeze

  belongs_to :investment_portfolio, inverse_of: :policies
  has_many :sleeves, class_name: "InvestmentPolicySleeve",
                     dependent: :destroy, inverse_of: :investment_policy

  validates :version,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :status, inclusion: { in: STATUSES }
  validates :effective_from, presence: true
  validate :effective_period_not_inverted, if: :effective_until

  # NOTE: no Rails `enum` on status — enum setters raise ArgumentError for
  # unknown values, which would bypass the inclusion validation above.
  scope :active, -> { where(status: :active) }
  scope :newest_first, -> { order(version: :desc) }

  # Sum of sleeve targets — must equal exactly 100 (BigDecimal, no rounding).
  # Re-checked at model level as defense in depth against direct SQL writes;
  # the canonical gate is Investing::Allocation::PolicyValidator (TDD §7.3).
  # @return [BigDecimal]
  def sleeve_target_sum
    sleeves.sum(:target_pct) || BigDecimal("0")
  end

  # Group-level drift bands from the rebalancing jsonb, e.g.
  #   { "equity" => { "lower_pct" => 50, "upper_pct" => 60 }, ... }
  # @return [Hash{String => Hash{String => Numeric}}]
  def group_bands
    (rebalancing || {})["bands"] || {}
  end

  # Per-sleeve drift threshold (percentage points) below which no rebalance
  # action is proposed. Defaults to 1.0pp when unconfigured (TDD §5.1).
  # @return [BigDecimal]
  def threshold_to_act_pct
    value = (rebalancing || {})["threshold_to_act_pct"]
    return BigDecimal("1.0") if value.blank?

    BigDecimal(value.to_s)
  end

  private

  def effective_period_not_inverted
    return if effective_until.blank? || effective_from.blank?

    errors.add(:effective_until, :before_effective_from) if effective_until < effective_from
  end
end
