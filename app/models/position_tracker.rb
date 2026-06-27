# frozen_string_literal: true

require 'bigdecimal'

class PositionTracker < ApplicationRecord
  include PositionTrackerFactory
  include PositionTracker::Queryable
  include PositionTracker::PnlCalculatable
  include PositionTracker::Indexable
  include PositionTracker::Broadcastable
  include PositionTracker::Lifecycle

  # `meta` accessor is the persisted thin shim (no config_snapshot blobs).
  # Promoted store_accessor readers fall back to this hash when the column is nil,
  # preserving backward compatibility for legacy read paths.

  PROMOTED_META_KEYS = %w[
    breakeven_locked trailing_stop_price index_key direction entry_path entry_strategy
    exit_path exit_reason highest_price lowest_price be_set profit_floor_rupees
    profit_floor_set_at profit_zone_state profit_zone_transitioned_at secured_sl_price
    secured_sl_rupees carry_mode carry_marked_at carry_roi_pct alpha_source
    signal_confidence expected_value signal_timestamp client_order_id
    decision execution entry_context dte_at_entry vix_at_entry iv_at_entry
    iv_percentile spread_guard_pct atm_strike expiry_date bos_age_at_entry
    retrace_pct pullback_candles entry_distance_r continuation_body_position
    time_from_bos_to_entry premium_stop_price entry_risk_rupees entry_tf htf_tf
    strategy_profile entry_underlying_price hwm_pnl_pct peak_premium_at
  ].freeze

  BOOLEAN_PROMOTED_KEYS = %w[breakeven_locked be_set].freeze

  PROMOTED_META_KEYS.each do |key|
    define_method(key) do
      val = self[key]
      return val unless val.nil?

      meta_hash[key.to_s]
    end

    define_method("#{key}=") do |val|
      casted = BOOLEAN_PROMOTED_KEYS.include?(key) ? ActiveModel::Type::Boolean.new.cast(val) : val
      self[key] = casted
    end
  end

  BOOLEAN_PROMOTED_KEYS.each do |key|
    define_method("#{key}?") do
      ActiveModel::Type::Boolean.new.cast(send(key))
    end
  end

  after_update_commit :record_alpha_outcome!, if: :alpha_signal_just_exited?

  has_one :meta_snapshot, class_name: 'PositionMetaSnapshot', dependent: :destroy
  delegate :config_snapshot, :config_version_hash, :entry_at, to: :meta_snapshot, allow_nil: true

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

  belongs_to :instrument, optional: false, inverse_of: :position_trackers
  belongs_to :watchable, polymorphic: true, optional: false
  has_one :trade_analytic, dependent: :destroy, inverse_of: :position_tracker
  has_one :trade_telemetry, class_name: 'TradeTelemetry', foreign_key: :tracker_id, dependent: :destroy,
                            inverse_of: :tracker

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

  def lock_breakeven!
    # rubocop:disable Rails/SkipsModelValidations
    update_columns(breakeven_locked: true, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def tradable
    watchable
  end

  def underlying_instrument
    if watchable.is_a?(Derivative)
      watchable.instrument
    elsif watchable.is_a?(Instrument)
      watchable
    else
      instrument
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

  def runtime_meta_fetch(key)
    key_s = key.to_s
    cached = Live::PositionRuntimeCache.instance.fetch(id)
    sym = key_s.to_sym
    return cached[sym] if cached.key?(sym)

    meta_hash[key_s]
  end

  private

  def alpha_signal_just_exited?
    alpha_source.present? && saved_change_to_status? && exited?
  end

  def record_alpha_outcome!
    if last_pnl_rupees.to_f.positive?
      Risk::LimitsGuard.record_win!
    else
      Risk::LimitsGuard.record_loss!
    end
  rescue StandardError => e
    Rails.logger.error("[PositionTracker] alpha outcome recording failed for ##{id}: #{e.message}")
  end

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
