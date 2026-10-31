# frozen_string_literal: true

# == Schema Information
#
# Table name: investment_holdings
#
#  id                      :bigint           not null, primary key
#  investment_portfolio_id :bigint           not null
#  instrument_id           :integer          not null
#  sleeve_key              :string(64)
#  source                  :string           default("manual"), not null
#  quantity                :decimal(20, 4)   default(0), not null
#  average_cost            :decimal(15, 4)
#  last_price              :decimal(15, 4)
#  last_valued_at          :datetime
#  externally_held         :boolean          default(FALSE), not null
#  broker_raw              :jsonb            not null
#  synced_at               :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Aggregated exposure to one instrument in one portfolio (TDD §3.3 D3).
# quantity/average_cost mirror the broker-reconciled view; the tax-lot ledger
# (InvestmentLot, Phase 3) is built from our own fills. Holdings are never
# deleted — sold-out positions are zeroed and retained for audit.
class InvestmentHolding < ApplicationRecord
  SOURCES = %w[dhan_sync manual external].freeze

  belongs_to :investment_portfolio, inverse_of: :holdings
  belongs_to :instrument

  validates :source, inclusion: { in: SOURCES }
  validates :quantity,
            numericality: { greater_than_or_equal_to: 0 }
  validates :instrument_id,
            uniqueness: { scope: :investment_portfolio_id }
  validates :sleeve_key,
            allow_nil: true,
            format: { with: /\A[a-z0-9_]+\z/, message: :invalid_sleeve_key }

  scope :held, -> { where("quantity > 0") }
  scope :for_sleeve, ->(key) { where(sleeve_key: key) }
  scope :unclassified, -> { where(sleeve_key: nil) }
  scope :broker_synced, -> { where(source: :dhan_sync) }
  scope :externally_held, -> { where(externally_held: true) }

  # Market value at the last known price (nil when never valued).
  # @return [BigDecimal, nil]
  def market_value
    return if last_price.blank?

    quantity * last_price
  end
end
