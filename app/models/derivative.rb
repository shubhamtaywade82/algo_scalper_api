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
  has_one  :watchlist_item,  lambda {
    where(active: true)
  }, as: :watchable, class_name: 'WatchlistItem', dependent: :nullify, inverse_of: :watchable
  has_many :position_trackers, as: :watchable, dependent: :destroy

  validates :security_id, presence: true, uniqueness: { scope: %i[symbol_name exchange segment] }
  validates :option_type, inclusion: { in: %w[CE PE], allow_blank: true }

  scope :options, -> { where.not(option_type: [nil, '']) }
  scope :futures, -> { where(option_type: [nil, '']) }

  # Find derivative by underlying symbol, strike price, expiry date, and option type
  # @param underlying_symbol [String] Underlying symbol (e.g., 'NIFTY', 'BANKNIFTY')
  # @param strike_price [Float, BigDecimal, String] Strike price
  # @param expiry_date [Date, String] Expiry date
  # @param option_type [String] 'CE' or 'PE'
  # @return [Derivative, nil] Matching derivative or nil
  def self.find_by_params(underlying_symbol:, strike_price:, expiry_date:, option_type:)
    expiry_obj = expiry_date.is_a?(Date) ? expiry_date : Date.parse(expiry_date.to_s)
    strike_bd = BigDecimal(strike_price.to_s)

    where(
      underlying_symbol: underlying_symbol.to_s.upcase,
      expiry_date: expiry_obj,
      option_type: option_type.to_s.upcase
    ).detect do |d|
      BigDecimal(d.strike_price.to_s) == strike_bd
    end
  end

  # Find derivative security_id by underlying symbol, strike price, expiry date, and option type
  # @param underlying_symbol [String] Underlying symbol (e.g., 'NIFTY', 'BANKNIFTY')
  # @param strike_price [Float, BigDecimal, String] Strike price
  # @param expiry_date [Date, String] Expiry date
  # @param option_type [String] 'CE' or 'PE'
  # @return [String, nil] Security ID or nil
  def self.find_security_id(underlying_symbol:, strike_price:, expiry_date:, option_type:)
    derivative = find_by_params(
      underlying_symbol: underlying_symbol,
      strike_price: strike_price,
      expiry_date: expiry_date,
      option_type: option_type
    )
    derivative&.security_id
  end

  # Places a market BUY order for the derivative (CE/PE) with risk-aware sizing.
  # @param qty [Integer, nil]
  # @param product_type [String]
  # @param index_cfg [Hash, nil]
  # @param meta [Hash]
  # @return [Object, nil]
  def buy_option!(qty: nil, product_type: 'INTRADAY', index_cfg: nil, meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise 'Derivative missing segment/security_id' if segment_code.blank? || security.blank?

    ltp = resolve_ltp(segment: segment_code, security_id: security, meta: meta)
    raise 'LTP unavailable' unless ltp

    quantity = if qty.to_i.positive?
                 qty.to_i
               else
                 config = index_cfg || { key: underlying_symbol, segment: segment_code }
                 Capital::Allocator.qty_for(
                   index_cfg: config,
                   entry_price: ltp.to_f,
                   derivative_lot_size: lot_size.to_i,
                   scale_multiplier: 1
                 )
               end
    return nil if quantity.to_i <= 0

    order = Orders.config.place_market(
      side: 'buy',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :buy, security_id: security),
        ltp: ltp,
        product_type: product_type
      }
    )
    return nil unless order.respond_to?(:order_id) && order.order_id.present?

    side_label = option_type.to_s.upcase == 'CE' ? 'long_ce' : 'long_pe'

    after_order_track!(
      instrument: instrument,
      order_no: order.order_id,
      segment: segment_code,
      security_id: security,
      side: side_label,
      qty: quantity,
      entry_price: ltp,
      symbol: symbol_name || display_name,
      index_key: (index_cfg || {})[:key]
    )

    order
  end

  # Places a market SELL order to exit the derivative position.
  # @param qty [Integer, nil]
  # @param meta [Hash]
  # @return [Object, nil]
  def sell_option!(qty: nil, meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise 'Derivative missing segment/security_id' if segment_code.blank? || security.blank?

    quantity = if qty.to_i.positive?
                 qty.to_i
               else
                 PositionTracker.active.where(
                   "(watchable_type = 'Derivative' AND watchable_id = ?) OR instrument_id = ?",
                   id, instrument_id
                 ).where(security_id: security).sum(:quantity).to_i
               end
    return nil if quantity <= 0

    Orders.config.place_market(
      side: 'sell',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :sell, security_id: security)
      }
    )
  end
end
