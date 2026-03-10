# frozen_string_literal: true

class TradeAnalytic < ApplicationRecord
  belongs_to :position_tracker

  validates :symbol, presence: true
  validates :entry_price, presence: true
  validates :exit_price, presence: true

  # MFE = (Highest Price - Entry Price) / Entry Price
  # MAE = (Lowest Price - Entry Price) / Entry Price
  def mfe_pct
    return 0 if entry_price.to_f.zero?
    max_favorable_excursion.to_f / entry_price.to_f
  end

  def mae_pct
    return 0 if entry_price.to_f.zero?
    max_adverse_excursion.to_f / entry_price.to_f
  end
end
