# frozen_string_literal: true

require 'bigdecimal'

class PositionTracker < ApplicationRecord
  include PositionTrackerFactory
  include PositionTracker::Queryable
  include PositionTracker::PnlCalculatable
  include PositionTracker::Indexable
  include PositionTracker::Broadcastable
  include PositionTracker::Lifecycle

  def peak_premium
    highest_price
  end

  def create_position_meta_snapshot!(config_version_hash:, config_change_log_id: nil, config_snapshot:, entry_at: nil)
    create_meta_snapshot!(
      config_version_hash: config_version_hash,
      config_change_log_id: config_change_log_id,
      config_snapshot: config_snapshot,
      entry_at: entry_at
    )
  end

  enum :status, {
    pending: 'pending',
    active: 'active',
    exited: 'exited',
    cancelled: 'cancelled'
  }

  validates :order_no, presence: true, uniqueness: true
  validates :security_id, presence: true
  validate :segment_must_be_tradable

  # Associations
  belongs_to :instrument, optional: false, inverse_of: :position_trackers
  belongs_to :watchable, polymorphic: true, optional: false
  has_one :trade_analytic, dependent: :destroy, inverse_of: :position_tracker
  has_one :trade_telemetry, class_name: 'TradeTelemetry', foreign_key: :tracker_id, dependent: :destroy,
                            inverse_of: :tracker

  # Instance Methods
  def metadata_for_index
    {
      id: id,
      security_id: security_id.to_s,
      entry_price: entry_price.presence&.to_s,
      quantity: quantity.to_i,
      segment: segment
    }
  end

  def state_machine
    Positions::States::PositionStateMachine.new(self)
  end

  def paper?
    paper == true
  end

  def live?
    !paper?
  end

  def be_set?
    ActiveModel::Type::Boolean.new.cast(be_set)
  end

  def breakeven_locked?
    ActiveModel::Type::Boolean.new.cast(meta_hash.fetch('breakeven_locked', false))
  end

  def lock_breakeven!
    Positions::MetaUpdater.new(tracker: self).update! do |meta|
      meta['breakeven_locked'] = true
      meta
    end
  end

  def tradable
    watchable
  end

  def record_alpha_outcome!
    if last_pnl_rupees.to_f.positive?
      Risk::LimitsGuard.record_win!
    else
      Risk::LimitsGuard.record_loss!
    end
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

  private

  def meta_hash
    value = self[:meta]
    value.is_a?(Hash) ? value : {}
  end

  def segment_must_be_tradable
    return if segment.blank?
    return if Orders::Placer::VALID_TRADABLE_SEGMENTS.include?(segment.to_s.upcase)

    errors.add(
      :segment,
      "is not tradable. Segment '#{segment}' is an index segment and cannot be traded. " \
      "Valid tradable segments: #{Orders::Placer::VALID_TRADABLE_SEGMENTS.join(', ')}"
    )
  end
end
