# == Schema Information
#
# Table name: position_trackers
#
#  id                        :integer         not null, primary key
#  instrument_id             :integer         not null
#  order_no                  :string          not null
#  security_id               :string          not null
#  symbol                    :string
#  segment                   :string
#  side                      :string
#  status                    :string          not null
#  quantity                  :integer
#  avg_price                 :decimal
#  entry_price               :decimal
#  last_pnl_rupees           :decimal
#  last_pnl_pct              :decimal
#  high_water_mark_pnl       :decimal
#  meta                      :jsonb
#  created_at                :datetime        not null
#  updated_at                :datetime        not null
#
# Indexes
#
#  index_position_trackers_on_instrument_id  (instrument_id)
#  index_position_trackers_on_order_no       (order_no) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (instrument_id => instruments.id)
#

# frozen_string_literal: true

require 'bigdecimal'

class PositionTracker < ApplicationRecord
  STATUSES = {
    pending: 'pending',
    active: 'active',
    exited: 'exited',
    cancelled: 'cancelled'
  }.freeze

  belongs_to :instrument

  store_accessor :meta, :breakeven_locked, :trailing_stop_price, :index_key, :direction

  validates :order_no, presence: true, uniqueness: true
  validates :security_id, presence: true
  validates :status, inclusion: { in: STATUSES.values }

  scope :active, -> { where(status: STATUSES[:active]) }
  scope :pending, -> { where(status: STATUSES[:pending]) }

  def mark_active!(avg_price:, quantity:)
    price = avg_price.present? ? BigDecimal(avg_price.to_s) : nil
    attrs = {
      status: STATUSES[:active],
      avg_price: price,
      entry_price: entry_price.presence || price,
      quantity: quantity
    }

    update!(attrs.compact)
    subscribe
  end

  def mark_cancelled!
    update!(status: STATUSES[:cancelled])
  end

  def mark_exited!
    Rails.logger.info("[PositionTracker] Exiting position #{order_no} - releasing capital and unsubscribing")

    # Unsubscribe from market feed
    unsubscribe

    # Clear Redis cache for this tracker
    Live::RedisPnlCache.instance.clear_tracker(id)

    # Update status
    update!(status: STATUSES[:exited])

    # Register cooldown to prevent immediate re-entry
    register_cooldown!

    Rails.logger.info("[PositionTracker] Position #{order_no} successfully exited and capital released")
  end

  def update_pnl!(pnl, pnl_pct: nil)
    pnl_value = BigDecimal(pnl.to_s)
    current_hwm = high_water_mark_pnl ? BigDecimal(high_water_mark_pnl.to_s) : BigDecimal(0)
    hwm = [current_hwm, pnl_value].max
    attrs = { last_pnl_rupees: pnl_value, high_water_mark_pnl: hwm }
    attrs[:last_pnl_pct] = BigDecimal(pnl_pct.to_s) if pnl_pct
    update!(attrs)
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

  def min_profit_lock(trail_step_pct)
    return BigDecimal(0) if trail_step_pct.to_f <= 0
    return BigDecimal(0) if entry_price.blank? || quantity.to_i <= 0

    BigDecimal(entry_price.to_s) * quantity.to_i * BigDecimal(trail_step_pct.to_s)
  end

  def breakeven_locked?
    ActiveModel::Type::Boolean.new.cast(meta_hash.fetch('breakeven_locked', false))
  end

  def lock_breakeven!
    update!(meta: meta_hash.merge('breakeven_locked' => true))
  end

  def unsubscribe
    segment_key = segment.presence || instrument&.exchange_segment
    return unless segment_key && security_id

    Rails.logger.debug { "[PositionTracker] Unsubscribing from market feed: #{segment_key}:#{security_id}" }
    Live::MarketFeedHub.instance.unsubscribe(segment: segment_key, security_id: security_id)

    # Also unsubscribe the underlying instrument if it's an option
    return unless instrument&.underlying_symbol

    underlying_instrument = Instrument.find_by(
      symbol_name: instrument.underlying_symbol,
      exchange: instrument.exchange,
      segment: instrument.segment
    )
    return unless underlying_instrument

    underlying_segment = underlying_instrument.exchange_segment
    return unless underlying_segment.present? && underlying_instrument.security_id.present?

    Rails.logger.debug do
      "[PositionTracker] Unsubscribing from underlying: #{underlying_instrument.symbol_name} "\
      "(#{underlying_segment}:#{underlying_instrument.security_id})"
    end
    Live::MarketFeedHub.instance.unsubscribe(
      segment: underlying_segment,
      security_id: underlying_instrument.security_id
    )
  end

  def subscribe
    segment_key = segment.presence || instrument&.exchange_segment
    return unless segment_key && security_id

    Live::MarketFeedHub.instance.subscribe(segment: segment_key, security_id: security_id)
  end

  private

  def register_cooldown!
    return if symbol.blank?

    Rails.cache.write("reentry:#{symbol}", Time.current, expires_in: 8.hours)
  end

  def meta_hash
    value = self[:meta]
    value.is_a?(Hash) ? value : {}
  end
end
