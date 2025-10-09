# frozen_string_literal: true

require "bigdecimal"

class PositionTracker < ApplicationRecord
  STATUSES = {
    pending: "pending",
    active: "active",
    exited: "exited",
    cancelled: "cancelled"
  }.freeze

  belongs_to :instrument, optional: true

  validates :order_no, presence: true, uniqueness: true
  validates :security_id, presence: true
  validates :status, inclusion: { in: STATUSES.values }

  scope :active, -> { where(status: STATUSES[:active]) }
  scope :pending, -> { where(status: STATUSES[:pending]) }

  def mark_active!(avg_price:, quantity:)
    price = avg_price ? BigDecimal(avg_price.to_s) : nil

    update!(
      status: STATUSES[:active],
      entry_price: entry_price || price,
      average_price: price,
      quantity: quantity,
      exchange_segment: exchange_segment.presence || instrument&.exchange_segment
    )
  end

  def mark_cancelled!
    update!(status: STATUSES[:cancelled])
  end

  def mark_exited!(price: nil, reason: nil)
    attrs = { status: STATUSES[:exited] }
    attrs[:exit_price] = BigDecimal(price.to_s) if price
    attrs[:exit_reason] = reason if reason
    update!(attrs)
  end

  def update_pnl!(pnl)
    pnl_value = BigDecimal(pnl.to_s)
    current_hwm = high_water_mark_pnl ? BigDecimal(high_water_mark_pnl.to_s) : BigDecimal("0")
    hwm = [ current_hwm, pnl_value ].max
    update!(last_pnl_rupees: pnl_value, high_water_mark_pnl: hwm)
  end

  def trailing_stop_triggered?(pnl, drop_pct)
    return false if high_water_mark_pnl.blank? || BigDecimal(high_water_mark_pnl.to_s).zero?

    pnl_value = BigDecimal(pnl.to_s)
    hwm_value = BigDecimal(high_water_mark_pnl.to_s)
    threshold = hwm_value * (1 - drop_pct)
    pnl_value <= threshold
  end

  def ready_to_trail?(pnl, min_profit)
    BigDecimal(pnl.to_s) >= min_profit
  end

  def unsubscribe
    segment = resolved_exchange_segment
    return unless segment

    Live::WsHub.instance.unsubscribe_option!(segment: segment, security_id: security_id)
  end

  def active?
    status == STATUSES[:active]
  end

  def buy?
    transaction_type.to_s.casecmp("BUY").zero?
  end

  def sell?
    transaction_type.to_s.casecmp("SELL").zero?
  end

  def strategy_key
    (strategy.presence || "index_options_buy").to_s
  end

  def resolved_exchange_segment
    exchange_segment.presence || instrument&.exchange_segment
  end
end
