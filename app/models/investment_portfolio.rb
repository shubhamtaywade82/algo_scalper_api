# frozen_string_literal: true

# == Schema Information
#
# Table name: investment_portfolios
#
#  id                      :bigint           not null, primary key
#  name                    :string           not null
#  base_currency           :string(3)        default("INR"), not null
#  investment_horizon_years :integer          default(10), not null
#  risk_profile            :string           default("balanced"), not null
#  status                  :string           default("active"), not null
#  broker_linkage          :string           default("manual"), not null
#  external_ref            :jsonb            not null
#  archived_at             :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Identity for one long-horizon investment portfolio (TDD §3).
# The Trading domain's intraday position tracking is a separate model
# universe — see docs/investing/TECHNICAL_DESIGN.md §2 hard boundaries.
class InvestmentPortfolio < ApplicationRecord
  RISK_PROFILES = %w[conservative balanced growth].freeze
  STATUSES = %w[active paused closed].freeze
  BROKER_LINKAGES = %w[dhan manual external].freeze
  CURRENCIES = %w[INR USD].freeze

  has_many :policies, class_name: "InvestmentPolicy", dependent: :destroy,
                      inverse_of: :investment_portfolio
  has_many :holdings, class_name: "InvestmentHolding", dependent: :destroy,
                      inverse_of: :investment_portfolio
  # Snapshots (InvestmentSnapshot) arrive with the full Phase-1 valuation
  # service (TDD §18 — deliberately outside the spike).

  validates :name, presence: true,
                   uniqueness: { case_sensitive: false },
                   length: { maximum: 120 }
  validates :base_currency, inclusion: { in: CURRENCIES }
  validates :investment_horizon_years,
            numericality: { only_integer: true,
                            greater_than_or_equal_to: 1,
                            less_than_or_equal_to: 50 }
  validates :risk_profile, inclusion: { in: RISK_PROFILES }
  validates :status, inclusion: { in: STATUSES }
  validates :broker_linkage, inclusion: { in: BROKER_LINKAGES }

  scope :active, -> { where(status: "active") }
  scope :dhan_linked, -> { where(broker_linkage: :dhan) }

  # The mandate this portfolio is currently governed by (TDD §3.3 D1:
  # at most one active policy — enforced by a partial unique index).
  # @return [InvestmentPolicy, nil]
  def active_policy
    policies.active.first
  end

  def active? = status == "active"
end
