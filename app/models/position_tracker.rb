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

  def register_in_index
    return unless active? && entry_price.present? && quantity.to_i.positive?

    Live::PositionIndex.instance.add(metadata_for_index)
  rescue StandardError => e
    Rails.logger.warn("[PositionTracker] register_in_index failed for #{id}: #{e.message}")
  end

  def subscribe_to_feed
    # Use same segment resolution logic as subscribe method
    segment_key = segment.presence || watchable&.exchange_segment || instrument&.exchange_segment
    return unless segment_key && security_id

    hub = Live::MarketFeedHub.instance
    hub.start! unless hub.running?

    # Check if already subscribed before calling hub
    if hub.subscribed?(segment: segment_key, security_id: security_id)
      Rails.logger.debug { "[PositionTracker] subscribe_to_feed: Already subscribed to #{segment_key}:#{security_id}, skipping" }
    else
      hub.subscribe(segment: segment_key, security_id: security_id)
    end

    Live::PositionIndex.instance.add(id: id, security_id: security_id, segment: segment_key, entry_price: entry_price,
                                     quantity: quantity)
  end

  def unregister_from_index
    # Remove from in-memory index
    Live::PositionIndex.instance.remove(id, security_id)

    # Remove Redis tick cache
    Live::RedisTickCache.instance.clear_tick(segment, security_id)

    # Remove in-memory TickCache
    Live::TickCache.delete(segment, security_id)

    # Unsubscribe websocket feed
    unsubscribe
  rescue StandardError => e
    Rails.logger.warn("[PositionTracker] unregister_from_index failed for #{id}: #{e.message}")
  end

  def cleanup_if_exited
    return unless saved_change_to_status? && exited?

    unregister_from_index
    clear_redis_pnl_cache
  end

  def refresh_index_if_relevant
    # If status, security_id, entry_price or quantity changed, update index
    unless saved_change_to_status? || saved_change_to_security_id? || saved_change_to_entry_price? || saved_change_to_quantity?
      return
    end

    unregister_from_index
    register_in_index
  end

  def resolve_exit_price(exit_price)
    exit_price ||= fetch_ltp_from_cache
    exit_price = BigDecimal(exit_price.to_s) if exit_price.present?
    exit_price
  end

  def fetch_ltp_from_cache
    seg = segment.presence || watchable&.exchange_segment || instrument&.exchange_segment
    tick = Live::TickQuery.for_security(segment: seg, security_id: security_id)
    tick&.ltp
  end

  def prepare_exit_metadata(exit_reason)
    exit_reason ||= meta.is_a?(Hash) ? meta['exit_reason'] : nil
    metadata = meta.is_a?(Hash) ? meta.dup : {}
    metadata['exit_reason'] = exit_reason if exit_reason.present?
    metadata['exit_triggered_at'] ||= Time.current
    metadata
  end

  def update_exit_attributes(exit_price, exited_at, metadata)
    attrs = {
      status: :exited,
      exit_price: exit_price,
      exited_at: exited_at || Time.current,
      last_pnl_rupees: last_pnl_rupees,
      last_pnl_pct: last_pnl_pct,
      high_water_mark_pnl: high_water_mark_pnl,
      meta: metadata
    }.compact

    update!(attrs)
  end

  def cleanup_exit_caches
    Live::PositionIndex.instance.remove(id, security_id)
    Live::RedisPnlCache.instance.clear_tracker(id)
    Live::RedisTickCache.instance.clear_tick(segment, security_id)
    Live::TickCache.delete(segment, security_id)
  end

  def register_cooldown!
    return if symbol.blank?

    Rails.cache.write("reentry:#{symbol}", Time.current, expires_in: 8.hours)
  end

  def clear_redis_cache_if_exited
    return unless saved_change_to_status? && exited?

    clear_redis_pnl_cache
  end

  def clear_redis_pnl_cache
    Live::RedisPnlCache.instance.clear_tracker(id)
  end

  def persist_final_pnl_from_cache
    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return unless cache

    if cache[:pnl]
      pnl_value = BigDecimal(cache[:pnl].to_s)
      self.last_pnl_rupees = pnl_value

      current_hwm = high_water_mark_pnl.present? ? BigDecimal(high_water_mark_pnl.to_s) : BigDecimal(0)
      hwm = cache[:hwm_pnl] ? BigDecimal(cache[:hwm_pnl].to_s) : current_hwm
      self.high_water_mark_pnl = [current_hwm, hwm, pnl_value].max

      # Store hwm_pnl_pct in meta if available
      if cache[:hwm_pnl_pct]
        meta = meta_hash.dup
        meta['hwm_pnl_pct'] = cache[:hwm_pnl_pct].to_f
        self.meta = meta
      end
    end

    self.last_pnl_pct = cache[:pnl_pct] ? BigDecimal(cache[:pnl_pct].to_s) : nil
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
