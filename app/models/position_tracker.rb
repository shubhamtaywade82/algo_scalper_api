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
  include PositionTrackerFactory

  # Attribute accessors
  store_accessor :meta, :breakeven_locked, :trailing_stop_price, :index_key, :direction

  # Enums
  enum :status, {
    pending: 'pending',
    active: 'active',
    exited: 'exited',
    cancelled: 'cancelled'
  }

  # Validations
  validates :order_no, presence: true, uniqueness: true
  validates :security_id, presence: true
  validate :segment_must_be_tradable

  # Callbacks
  after_commit :register_in_index, on: %i[create update]
  after_commit :unregister_from_index, on: :destroy
  after_update_commit :refresh_index_if_relevant
  after_update_commit :cleanup_if_exited
  after_create_commit :subscribe_to_feed
  after_destroy_commit :clear_redis_pnl_cache
  after_update_commit :clear_redis_cache_if_exited

  # Associations
  belongs_to :instrument # Kept for backward compatibility during transition
  belongs_to :watchable, polymorphic: true

  # Scopes
  # Note: enum automatically creates scopes for :pending, :active, :exited, :cancelled
  scope :paper, -> { where(paper: true) }
  scope :live, -> { where(paper: false) }
  scope :exited_paper, -> { where(paper: true, status: :exited) }

  # Class Methods
  class << self
    def active_for(seg, sid)
      where(segment: seg, security_id: sid, status: :active).first
    end

    def exited_for(seg, sid)
      where(segment: seg, security_id: sid, status: :exited).order(id: :desc).first
    end

    def paper_trading_stats_with_pct
      exited = exited_paper
      active = paper.active

      active_count = active.count
      realized_pnl_rupees = exited.sum { |t| t.last_pnl_rupees.to_f }
      # Use current_pnl_rupees for active positions (reads from Redis cache for live values)
      unrealized_pnl_rupees = active.sum { |t| t.current_pnl_rupees.to_f }

      total_pnl_rupees = realized_pnl_rupees + unrealized_pnl_rupees

      # Calculate PnL percentages based on initial capital, not by summing individual trade percentages
      initial_capital = Capital::Allocator.paper_trading_balance.to_f
      realized_pnl_pct = initial_capital.positive? ? (realized_pnl_rupees / initial_capital * 100.0) : 0.0
      unrealized_pnl_pct = initial_capital.positive? ? (unrealized_pnl_rupees / initial_capital * 100.0) : 0.0
      total_pnl_pct = initial_capital.positive? ? (total_pnl_rupees / initial_capital * 100.0) : 0.0

      # Calculate average per-trade percentages (for reference)
      avg_realized_pnl_pct = if exited.any?
                               (exited.map do |t|
                                 t.last_pnl_pct.to_f
                               end.compact.sum / exited.count.to_f).round(2)
                             else
                               0.0
                             end
      avg_unrealized_pnl_pct = if active.any?
                                 (active.map do |t|
                                   (t.current_pnl_pct || 0).to_f
                                 end.compact.sum / active.count.to_f).round(2)
                               else
                                 0.0
                               end

      {
        total_trades: exited.count,
        active_positions: active_count,
        total_pnl_rupees: total_pnl_rupees.round(2),
        total_pnl_pct: total_pnl_pct.round(2),
        realized_pnl_rupees: realized_pnl_rupees.round(2),
        realized_pnl_pct: realized_pnl_pct.round(2),
        unrealized_pnl_rupees: unrealized_pnl_rupees.round(2),
        unrealized_pnl_pct: unrealized_pnl_pct.round(2),
        win_rate: paper_win_rate,
        avg_realized_pnl_pct: avg_realized_pnl_pct,
        avg_unrealized_pnl_pct: avg_unrealized_pnl_pct,
        winners: exited.count { |t| (t.last_pnl_rupees || 0).positive? },
        losers: exited.count { |t| (t.last_pnl_rupees || 0).negative? }
      }
    end

    def paper_positions_details
      paper.includes(:instrument).map do |t|
        entry_price = t.entry_price.to_f
        exit_price = t.last_pnl_rupees.present? && t.status == 'exited' ? t.exit_price.to_f : nil
        current_price = exit_price || t.avg_price.to_f
        side = t.side
        qty = t.quantity.to_i
        pnl_abs = t.last_pnl_rupees.to_f
        pnl_pct = if t.last_pnl_pct.present?
                    t.last_pnl_pct.to_f
                  elsif entry_price.positive? && current_price.positive?
                    if side == 'BUY'
                      ((current_price - entry_price) / entry_price * 100.0)
                    else
                      ((entry_price - current_price) / entry_price * 100.0)
                    end
                  else
                    0.0
                  end

        {
          id: t.id,
          order_no: t.order_no,
          symbol: t.symbol,
          side: side,
          status: t.status,
          quantity: qty,
          entry_price: entry_price,
          exit_price: exit_price,
          avg_price: t.avg_price.to_f,
          last_pnl_rupees: pnl_abs.round(2),
          last_pnl_pct: pnl_pct.round(2),
          high_water_mark_pnl: t.high_water_mark_pnl.to_f,
          created_at: t.created_at&.strftime('%Y-%m-%d %H:%M'),
          updated_at: t.updated_at&.strftime('%Y-%m-%d %H:%M'),
          watchable_type: t.watchable_type,
          segment: t.segment,
          security_id: t.security_id,
          paper: t.paper?,
          unrealized?: t.status != 'exited'
        }
      end
    end

    def total_paper_pnl
      exited_paper.sum do |tracker|
        tracker.last_pnl_rupees || BigDecimal(0)
      end
    end

    def active_paper_positions_count
      paper.active.count
    end

    def paper_win_rate
      exited = exited_paper
      return 0.0 if exited.empty?

      winners = exited.count { |t| (t.last_pnl_rupees || 0).positive? }
      (winners.to_f / exited.count * 100).round(2)
    end

    def paper_trading_stats
      exited = exited_paper
      active = paper.active
      active_count = active.count

      # Calculate realized PnL from exited positions
      realized_pnl = total_paper_pnl.to_f

      # Calculate unrealized PnL from active positions (use Redis cache)
      unrealized_pnl = active.sum do |tracker|
        tracker.current_pnl_rupees.to_f
      end

      # Total PnL = realized (exited) + unrealized (active)
      total_pnl = realized_pnl + unrealized_pnl

      {
        total_trades: exited.count,
        active_positions: active_count,
        total_pnl: total_pnl,
        realized_pnl: realized_pnl,
        unrealized_pnl: unrealized_pnl,
        win_rate: paper_win_rate,
        average_pnl: exited.empty? ? 0.0 : (realized_pnl / exited.count).to_f,
        winners: exited.count { |t| (t.last_pnl_rupees || 0).positive? },
        losers: exited.count { |t| (t.last_pnl_rupees || 0).negative? }
      }
    end

    def clear_orphaned_redis_pnl!
      return unless should_clear_orphaned?

      cache = Live::RedisPnlCache.instance
      # Only check active positions (most common case) - faster query
      existing_ids = PositionTracker.active.pluck(:id).to_set(&:to_s)

      cache.each_tracker_key do |_key, tracker_id|
        next if existing_ids.include?(tracker_id)

        Rails.logger.warn("[PositionTracker] Clearing orphaned Redis PnL cache for tracker #{tracker_id}")
        cache.clear_tracker(tracker_id)
      end

      @last_clear = Time.current
    end

    def should_clear_orphaned?
      @last_clear ||= 5.minutes.ago
      return true if Time.current - @last_clear >= 5.minutes

      false
    end
  end

  # Instance Methods
  def metadata_for_index
    {
      id: id,
      security_id: security_id.to_s,
      entry_price: entry_price.present? ? entry_price.to_s : nil,
      quantity: quantity.to_i,
      segment: segment
    }
  end

  def mark_active!(avg_price:, quantity:)
    price = avg_price.present? ? BigDecimal(avg_price.to_s) : nil
    attrs = {
      status: :active,
      avg_price: price,
      entry_price: entry_price.presence || price,
      quantity: quantity
    }

    update!(attrs.compact)
    subscribe

    # Initialize PnL in Redis (will be 0 initially since entry_price = avg_price)
    # This ensures the position is tracked in Redis from the start
    return if price.blank?

    initial_pnl = BigDecimal(0)
    Live::RedisPnlCache.instance.store_pnl(
      tracker_id: id,
      pnl: initial_pnl,
      pnl_pct: 0.0,
      ltp: price,
      hwm: initial_pnl,
      timestamp: Time.current,
      tracker: self
    )
  end

  def mark_cancelled!
    update!(status: :cancelled)
  end

  def paper?
    paper == true
  end

  def live?
    !paper?
  end

  def mark_exited!(exit_price: nil, exited_at: nil, exit_reason: nil)
    # Persist final PnL from Redis cache to DB (force sync, no throttling)
    persist_final_pnl_from_cache

    exit_price = resolve_exit_price(exit_price)
    metadata = prepare_exit_metadata(exit_reason)

    update_exit_attributes(exit_price, exited_at, metadata)
    cleanup_exit_caches
    unsubscribe
    register_cooldown!

    # Force final sync to DB (bypass throttling) to ensure final values are persisted
    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    if cache && cache[:pnl]
      Live::RedisPnlCache.instance.sync_pnl_to_database(
        id,
        cache[:pnl],
        cache[:pnl_pct],
        cache[:hwm_pnl],
        cache[:hwm_pnl_pct]
      )
    end

    self
  end

  def hydrate_pnl_from_cache!
    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return unless cache

    cache_live_pnl(cache[:pnl], pnl_pct: cache[:pnl_pct]) if cache[:pnl]

    self.high_water_mark_pnl = BigDecimal(cache[:hwm_pnl].to_s) if cache[:hwm_pnl]
  rescue StandardError
    nil
  end

  # Get current PnL from Redis cache (preferred) or fallback to DB
  # This avoids frequent DB reads - Redis is the source of truth for active positions
  def current_pnl_rupees
    return last_pnl_rupees if exited? # Exited positions: use DB (final value)

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return BigDecimal(cache[:pnl].to_s) if cache && cache[:pnl]

    last_pnl_rupees || BigDecimal(0)
  rescue StandardError
    last_pnl_rupees || BigDecimal(0)
  end

  # Get current PnL percentage from Redis cache (preferred) or fallback to DB
  def current_pnl_pct
    return last_pnl_pct if exited? # Exited positions: use DB (final value)

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return BigDecimal(cache[:pnl_pct].to_s) if cache && cache[:pnl_pct]

    last_pnl_pct
  rescue StandardError
    last_pnl_pct
  end

  # Get current high water mark from Redis cache (preferred) or fallback to DB
  def current_hwm_pnl
    return high_water_mark_pnl if exited? # Exited positions: use DB (final value)

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return BigDecimal(cache[:hwm_pnl].to_s) if cache && cache[:hwm_pnl]

    high_water_mark_pnl || BigDecimal(0)
  rescue StandardError
    high_water_mark_pnl || BigDecimal(0)
  end

  # Get current high water mark percentage from Redis cache (preferred) or fallback to meta
  def current_hwm_pnl_pct
    return meta_hash['hwm_pnl_pct'] if exited? # Exited positions: use meta (final value)

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return cache[:hwm_pnl_pct].to_f if cache && cache[:hwm_pnl_pct]

    meta_hash['hwm_pnl_pct']
  rescue StandardError
    meta_hash['hwm_pnl_pct']
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
    return unless Live::MarketFeedHub.instance.running?

    segment_key = segment.presence || watchable&.exchange_segment || instrument&.exchange_segment
    return unless segment_key && security_id

    # Never unsubscribe from IDX_I (index feeds) - they're needed for signal generation
    # and may be used by multiple positions
    if segment_key == 'IDX_I'
      Rails.logger.debug { "[PositionTracker] Skipping unsubscribe for IDX_I:#{security_id} (index feed must stay subscribed)" }
      return
    end

    # Rails.logger.debug { "[PositionTracker] Unsubscribing from market feed: #{segment_key}:#{security_id}" }
    Live::MarketFeedHub.instance.unsubscribe(segment: segment_key, security_id: security_id)

    # Never unsubscribe from underlying instruments (especially IDX_I)
    # They are needed for signal generation and may be used by other positions
    # The underlying index feeds should remain subscribed at all times
  end

  def subscribe
    segment_key = segment.presence || watchable&.exchange_segment || instrument&.exchange_segment
    return unless segment_key && security_id

    hub = Live::MarketFeedHub.instance
    # Ensure hub is running (will start if not running)
    hub.start! unless hub.running?

    # Check if already subscribed before calling hub
    if hub.subscribed?(segment: segment_key, security_id: security_id)
      Rails.logger.debug { "[PositionTracker] Already subscribed to #{segment_key}:#{security_id}, skipping" }
      return { segment: segment_key, security_id: security_id, already_subscribed: true }
    end

    hub.subscribe(segment: segment_key, security_id: security_id)
  rescue StandardError => e
    Rails.logger.error("[PositionTracker] Failed to subscribe #{order_no}: #{e.message}")
    nil
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

  def cache_live_pnl(pnl, pnl_pct: nil)
    pnl_value = BigDecimal(pnl.to_s)
    self.last_pnl_rupees = pnl_value

    self.last_pnl_pct = pnl_pct.nil? ? nil : BigDecimal(pnl_pct.to_s)

    current_hwm = high_water_mark_pnl.present? ? BigDecimal(high_water_mark_pnl.to_s) : BigDecimal(0)
    self.high_water_mark_pnl = [current_hwm, pnl_value].max
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
    Live::TickCache.ltp(seg, security_id)
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

  def calculate_paper_pnl(exit_price = nil)
    return BigDecimal(0) unless paper? && entry_price.present? && quantity.present?

    exit = exit_price || last_pnl_rupees
    return BigDecimal(0) unless exit

    entry = BigDecimal(entry_price.to_s)
    exit_value = BigDecimal(exit.to_s)
    qty = quantity.to_i

    # For long positions: PnL = (exit - entry) * quantity
    pnl = (exit_value - entry) * qty
    BigDecimal(pnl.to_s)
  end

  def segment_must_be_tradable
    return if segment.blank? # Allow blank segments (will be validated elsewhere if needed)

    return if Orders::Placer::VALID_TRADABLE_SEGMENTS.include?(segment.to_s.upcase)

    errors.add(
      :segment,
      "is not tradable. Segment '#{segment}' is an index segment and cannot be traded. " \
      "Valid tradable segments: #{Orders::Placer::VALID_TRADABLE_SEGMENTS.join(', ')}"
    )
  end
end
