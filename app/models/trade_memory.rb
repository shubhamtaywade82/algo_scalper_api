# == Schema Information
#
# Table name: trade_memories
#
#  id                   :bigint           not null, primary key
#  position_tracker_id  :bigint           not null
#  trade_analytic_id    :bigint
#  symbol               :string
#  strategy_name        :string
#  regime_at_entry      :string
#  regime_at_exit       :string
#  entry_quality_score  :decimal(5, 2)
#  exit_efficiency_pct  :decimal(6, 2)
#  pnl_rupees           :decimal(12, 4)
#  exit_reason          :string
#  lesson               :text             not null
#  category             :string           default("general"), not null
#  confidence           :decimal(3, 2)    default(0.5)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#

# frozen_string_literal: true

# Structured, queryable lesson extracted from a closed trade.
#
# This is the functional TradeMemory the architecture review's Phase 1
# flagged as missing: TradingBot::SelfLearning was a stub that always
# returned an empty trade list and only logged lessons to Rails.logger
# (never persisted them). Ai::Agents::PostTradeAnalysisAgent populates this
# table from real PositionTracker/TradeAnalytic data so downstream agents
# (Strategy Selection, Calibration) have something durable to query.
class TradeMemory < ApplicationRecord
  belongs_to :position_tracker
  belongs_to :trade_analytic, optional: true

  validates :lesson, presence: true
  validates :position_tracker_id, uniqueness: true

  scope :for_symbol, ->(symbol) { where(symbol: symbol.to_s.upcase) }
  scope :for_strategy, ->(name) { where(strategy_name: name) }
  scope :by_category, ->(category) { where(category: category.to_s) }
  scope :recent, -> { order(created_at: :desc) }

  def winner? = pnl_rupees.to_f.positive?
  def loser? = pnl_rupees.to_f.negative?
end
