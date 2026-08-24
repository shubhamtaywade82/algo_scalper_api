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

  def long_position?
    position_side == 'long'
  end

  def short_position?
    position_side == 'short'
  end

  def create_position_meta_snapshot!(config_version_hash:, config_snapshot:, config_change_log_id: nil, entry_at: nil)
    create_meta_snapshot!(
      config_version_hash: config_version_hash,
      config_change_log_id: config_change_log_id,
      config_snapshot: config_snapshot,
      entry_at: entry_at
    )
  end

  # Attribute accessors
  #
  # index_key, entry_strategy, breakeven_locked, and be_set are deliberately NOT store_accessors
  # here — all four are real, indexed/typed columns on this table, and a store_accessor on top
  # shadows every SQL `.where(...)` query (and, for breakeven_locked/be_set, the plain non-`?`
  # reader) with the always-empty column while reads/writes silently go through `meta` instead.
  # That broke DirectionConflictGuard, OptionsBuying::PerformanceDb, and PositionTracker#lock_
  # breakeven! (via Positions::MetaUpdater/MetaPatch, see PROMOTED_META_KEYS below). Fixed
  # 2026-08-13 — see backfill in db/migrate for the historical `meta`-only records.
  #
  # trailing_stop_price/highest_price/lowest_price/profit_floor_rupees/profit_floor_set_at/
  # profit_zone_state/profit_zone_transitioned_at/secured_sl_price/secured_sl_rupees/direction/
  # entry_path/exit_path/exit_reason stay store_accessors on purpose: they're written directly
  # into `meta` from hot tick-path code (Live::TrailingEngine, Orders::MfeExitEngine,
  # RiskManagerService::ExitEnforcement) that bypasses this accessor entirely — unshadowing them
  # without also rewriting those hot paths to write the real column would make the accessor
  # silently stop reflecting what the trailing/exit engines just set. Left alone; PROMOTED_META_KEYS
  # excludes them for the same reason.
  store_accessor :meta, :trailing_stop_price, :direction, :entry_path,
                 :exit_path, :exit_reason, :highest_price, :lowest_price, :profit_floor_rupees,
                 :profit_floor_set_at, :profit_zone_state, :secured_sl_price, :secured_sl_rupees,
                 :profit_zone_transitioned_at

  # Meta keys that have a matching real column AND are safe for Positions::MetaUpdater/MetaPatch
  # to scrub out of `meta` into that column — i.e. NOT one of the still-shadowed store_accessor
  # fields above (promoting one of those here would silently break its accessor the same way
  # breakeven_locked did). See db/migrate/20260625000002_..._extract_snapshots.rb for the
  # original (broader, aspirational) PROMOTED_KEYS this was trimmed down from.
  PROMOTED_META_KEYS = %w[
    breakeven_locked index_key entry_strategy be_set carry_mode carry_marked_at carry_roi_pct
    alpha_source signal_confidence expected_value signal_timestamp client_order_id
    leg_group_id leg_index leg_role premium_received
  ].freeze

  BOOLEAN_PROMOTED_KEYS = %w[breakeven_locked be_set].freeze

  # Enums
  enum :status, {
    pending: 'pending',
    active: 'active',
    exited: 'exited',
    cancelled: 'cancelled'
  }

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
  after_update_commit :analyze_trade_if_exited

  # Associations
  belongs_to :instrument # Kept for backward compatibility during transition
  belongs_to :leg_group, optional: true
  belongs_to :watchable, polymorphic: true
  has_one :trade_analytic, dependent: :destroy
  has_one :trade_memory, dependent: :destroy
  has_one :meta_snapshot, class_name: 'PositionMetaSnapshot', dependent: :destroy

  # Scopes
  # Note: enum automatically creates scopes for :pending, :active, :exited, :cancelled
  scope :paper, -> { where(paper: true) }
  scope :live, -> { where(paper: false) }
  scope :exited_paper, -> { where(paper: true, status: :exited) }
  # Active with exit requested but not yet exited (stuck if order failed or pending)
  scope :active_with_exit_requested, -> { active.where.not(exit_requested_at: nil) }

  # Class Methods
  class << self
    def active_for(seg, sid)
      where(segment: seg, security_id: sid, status: :active).first
    end

    def exited_for(seg, sid)
      where(segment: seg, security_id: sid, status: :exited).order(id: :desc).first
    end

    def paper_trading_stats_with_pct(date: nil)
      # Filter by date if provided, otherwise use all exited positions
      if date
        date_start = date.beginning_of_day
        date_end = date.end_of_day
        exited = exited_paper.where(exited_at: date_start..date_end)
      else
        # Default: only today's exited positions
        today_start = Time.zone.today.beginning_of_day
        today_end = Time.zone.today.end_of_day
        exited = exited_paper.where(exited_at: today_start..today_end)
      end
      active = paper.active
      # Load once to avoid multiple queries (any? + count + iteration)
      exited = exited.load
      active = active.load

      active_count = active.size
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
      # last_pnl_pct is stored as decimal (0.0573), convert to percentage for display
      avg_realized_pnl_pct = if exited.any?
                               (exited.filter_map do |t|
                                 t.last_pnl_pct.to_f * 100.0
                               end.sum / exited.size.to_f).round(2)
                             else
                               0.0
                             end
      # current_pnl_pct returns decimal from Redis, convert to percentage for display
      avg_unrealized_pnl_pct = if active.any?
                                 (active.filter_map do |t|
                                   (t.current_pnl_pct || 0).to_f * 100.0
                                 end.sum / active.size.to_f).round(2)
                               else
                                 0.0
                               end

      {
        total_trades: exited.size,
        active_positions: active_count,
        total_pnl_rupees: total_pnl_rupees.round(2),
        total_pnl_pct: total_pnl_pct.round(2),
        realized_pnl_rupees: realized_pnl_rupees.round(2),
        realized_pnl_pct: realized_pnl_pct.round(2),
        unrealized_pnl_rupees: unrealized_pnl_rupees.round(2),
        unrealized_pnl_pct: unrealized_pnl_pct.round(2),
        win_rate: paper_win_rate(date: date, exited: exited),
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
        # last_pnl_pct is stored as decimal (0.0573), convert to percentage for display
        pnl_pct = if t.last_pnl_pct.present?
                    t.last_pnl_pct.to_f * 100.0
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

    def paper_win_rate(date: nil, exited: nil)
      # Use preloaded collection when provided to avoid duplicate query
      if !exited.nil? && exited.respond_to?(:size) && exited.respond_to?(:count)
        return 0.0 if exited.empty?

        winners = exited.count { |t| (t.last_pnl_rupees || 0).positive? }
        return (winners.to_f / exited.size * 100).round(2)
      end

      # Filter by date if provided, otherwise use today's exited positions
      if date
        date_start = date.beginning_of_day
        date_end = date.end_of_day
        exited = exited_paper.where(exited_at: date_start..date_end)
      else
        # Default: only today's exited positions
        today_start = Time.zone.today.beginning_of_day
        today_end = Time.zone.today.end_of_day
        exited = exited_paper.where(exited_at: today_start..today_end)
      end
      exited = exited.load
      return 0.0 if exited.empty?

      winners = exited.count { |t| (t.last_pnl_rupees || 0).positive? }
      (winners.to_f / exited.size * 100).round(2)
    end

    def paper_trading_stats
      exited = exited_paper.load
      active = paper.active.load
      active_count = active.size

      # Calculate realized PnL from exited positions
      realized_pnl = total_paper_pnl.to_f

      # Calculate unrealized PnL from active positions (use Redis cache)
      unrealized_pnl = active.sum do |tracker|
        tracker.current_pnl_rupees.to_f
      end

      # Total PnL = realized (exited) + unrealized (active)
      total_pnl = realized_pnl + unrealized_pnl

      {
        total_trades: exited.size,
        active_positions: active_count,
        total_pnl: total_pnl,
        realized_pnl: realized_pnl,
        unrealized_pnl: unrealized_pnl,
        win_rate: paper_win_rate,
        average_pnl: exited.empty? ? 0.0 : (realized_pnl / exited.size).to_f,
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

  def analyze_trade_if_exited
    return unless saved_change_to_status? && exited?

    Optimization::TradeAnalyzer.call(self)
  end

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

  def runtime_meta_fetch(key)
    key_s = key.to_s
    cached = Live::PositionRuntimeCache.instance.fetch(id)
    sym = key_s.to_sym
    return cached[sym] if cached.key?(sym)

    meta_hash[key_s]
  end
  public :runtime_meta_fetch

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
