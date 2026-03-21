# == Schema Information
#
# Table name: trade_analytics
#
#  id                      :integer          not null, primary key
#  position_tracker_id     :integer          not null
#  symbol                  :string
#  entry_price             :decimal(, )
#  exit_price              :decimal(, )
#  max_favorable_excursion :decimal(, )
#  max_adverse_excursion   :decimal(, )
#  duration_seconds        :integer
#  volatility              :decimal(, )
#  strategy                :string
#  exit_reason             :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_trade_analytics_on_position_tracker_id  (position_tracker_id)
#

# frozen_string_literal: true

class TradeAnalytic < ApplicationRecord
  belongs_to :position_tracker, optional: false, inverse_of: :trade_analytic

  validates :symbol, presence: true
  validates :entry_price, presence: true
  validates :exit_price, presence: true

  # MFE = (Highest Price - Entry Price) / Entry Price
  # MAE = (Lowest Price - Entry Price) / Entry Price
  def mfe_pct
    return 0 if entry_price.to_f.zero?
    max_favorable_excursion.to_f / entry_price
  end

  def mae_pct
    return 0 if entry_price.to_f.zero?
    max_adverse_excursion.to_f / entry_price
  end
end
