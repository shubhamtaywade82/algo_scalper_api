# frozen_string_literal: true

# Aggregate root of the Investing domain (TDD §3.1).
# Long-horizon (5-10y) portfolio; deliberately shares NOTHING with
# PositionTracker — see docs/investing/TECHNICAL_DESIGN.md §1.3.4.
class InvestmentPortfolio < ApplicationRecord
  MODES = %w[paper live].freeze

  has_many :investment_policies, dependent: :destroy
  has_many :investment_holdings, dependent: :destroy
  has_many :investment_snapshots, dependent: :destroy
  has_many :investment_rebalances, dependent: :destroy
  has_many :investment_transactions, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :mode, inclusion: { in: MODES }
  validates :base_currency, presence: true
  validates :cash_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :invested_amount, numericality: { greater_than_or_equal_to: 0 }

  # Live portfolios additionally require the Phase-4 safety rails (TDD §19.2).
  validate :live_mode_gate, on: :create

  def active_policy
    investment_policies.find_by(status: 'active')
  end

  def execution_paused?
    ActiveModel::Type::Boolean.new.cast(meta['execution_paused']) == true
  end

  private

  def live_mode_gate
    return unless mode == 'live'
    return if ENV['INVESTING_LIVE_CONFIRMED'] == 'yes'

    errors.add(:mode, 'live mode requires INVESTING_LIVE_CONFIRMED=yes (Phase 4 gate, TDD §19.2)')
  end
end
