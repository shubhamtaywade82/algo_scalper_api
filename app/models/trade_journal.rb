# frozen_string_literal: true

# Post-trade analysis record.
# Created when a position closes, capturing full trade lifecycle.
class TradeJournal < ApplicationRecord
  belongs_to :position_tracker
  belongs_to :instrument

  validates :side, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :entry_price, presence: true, numericality: { greater_than: 0 }
  validates :entry_time, presence: true

  scope :winners, -> { where('net_pnl > 0') }
  scope :losers, -> { where('net_pnl < 0') }
  scope :paper, -> { where(paper: true) }
  scope :live, -> { where(paper: false) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..) }
  scope :for_strategy, ->(name) { where(strategy_name: name) }

  def winner? = net_pnl.to_f.positive?
  def loser? = net_pnl.to_f.negative?

  def r_multiple
    return nil unless max_adverse_excursion&.positive?

    net_pnl.to_f / max_adverse_excursion
  end
end
