# == Schema Information
#
# Table name: derivatives
#
#  id                            :integer          not null, primary key
#  instrument_id                 :integer          not null
#  exchange                      :string
#  segment                       :string
#  security_id                   :string
#  isin                          :string
#  instrument_code               :string
#  underlying_security_id        :string
#  underlying_symbol             :string
#  symbol_name                   :string
#  display_name                  :string
#  instrument_type               :string
#  series                        :string
#  lot_size                      :integer
#  expiry_date                   :date
#  strike_price                  :decimal(, )
#  option_type                   :string
#  tick_size                     :decimal(, )
#  expiry_flag                   :string
#  bracket_flag                  :string
#  cover_flag                    :string
#  asm_gsm_flag                  :string
#  asm_gsm_category              :string
#  buy_sell_indicator            :string
#  buy_co_min_margin_per         :decimal(, )
#  sell_co_min_margin_per        :decimal(, )
#  buy_co_sl_range_max_perc      :decimal(, )
#  sell_co_sl_range_max_perc     :decimal(, )
#  buy_co_sl_range_min_perc      :decimal(, )
#  sell_co_sl_range_min_perc     :decimal(, )
#  buy_bo_min_margin_per         :decimal(, )
#  sell_bo_min_margin_per        :decimal(, )
#  buy_bo_sl_range_max_perc      :decimal(, )
#  sell_bo_sl_range_max_perc     :decimal(, )
#  buy_bo_sl_range_min_perc      :decimal(, )
#  sell_bo_sl_min_range          :decimal(, )
#  buy_bo_profit_range_max_perc  :decimal(, )
#  sell_bo_profit_range_max_perc :decimal(, )
#  buy_bo_profit_range_min_perc  :decimal(, )
#  sell_bo_profit_range_min_perc :decimal(, )
#  mtf_leverage                  :decimal(, )
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_derivatives_on_instrument_code                    (instrument_code)
#  index_derivatives_on_instrument_id                      (instrument_id)
#  index_derivatives_on_symbol_name                        (symbol_name)
#  index_derivatives_on_underlying_symbol_and_expiry_date  (underlying_symbol,expiry_date)
#  index_derivatives_unique                                (security_id,symbol_name,exchange,segment) UNIQUE
#

# frozen_string_literal: true

class Derivative < ApplicationRecord
  include InstrumentHelpers

  belongs_to :instrument
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_one  :watchlist_item,  -> { where(active: true) }, as: :watchable, class_name: "WatchlistItem"

  validates :security_id, presence: true, uniqueness: { scope: [ :symbol_name, :exchange, :segment ] }
  validates :option_type, inclusion: { in: %w[CE PE], allow_blank: true }

  scope :options, -> { where.not(option_type: [ nil, "" ]) }
  scope :futures, -> { where(option_type: [ nil, "" ]) }
end
