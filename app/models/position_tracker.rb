# frozen_string_literal: true

require 'bigdecimal'

class PositionTracker < ApplicationRecord
  include PositionTrackerFactory
  include PositionTracker::Queryable
  include PositionTracker::PnlCalculatable
  include PositionTracker::Indexable
  include PositionTracker::Broadcastable
  include PositionTracker::Lifecycle

  # Attribute accessors
  store_accessor :meta, :breakeven_locked, :trailing_stop_price, :index_key, :direction, :entry_path, :entry_strategy,
                 :exit_path, :exit_reason, :highest_price

  enum :status, {
    pending: 'pending',
    active: 'active',
    exited: 'exited',
    cancelled: 'cancelled'
  }

  validates :order_no, presence: true, uniqueness: true
  validates :security_id, presence: true
  validate :segment_must_be_tradable

  ORPHANED_CLEAR_INTERVAL = 5.minutes

  # Callbacks
  after_commit :register_in_index, on: %i[create update], if: :index_registration_relevant?
  after_commit :unregister_from_index, on: :destroy
  after_update_commit :refresh_index_if_relevant
  after_update_commit :cleanup_if_exited
  after_create_commit :subscribe_to_feed, if: :feed_subscription_relevant?
  after_destroy_commit :clear_redis_pnl_cache
  after_update_commit :clear_redis_cache_if_exited

  # Associations
  belongs_to :instrument, optional: false, inverse_of: :position_trackers # Kept for backward compatibility during transition
  belongs_to :watchable, polymorphic: true, optional: false
  has_one :trade_analytic, dependent: :destroy, inverse_of: :position_tracker
  has_one :trade_telemetry, class_name: 'TradeTelemetry', foreign_key: :tracker_id, dependent: :destroy,
                            inverse_of: :tracker

  # Scopes
  # Note: enum automatically creates scopes for :pending, :active, :exited, :cancelled
  scope :paper, -> { where(paper: true) }
  scope :live, -> { where(paper: false) }
  scope :exited_paper, -> { where(paper: true, status: :exited) }
  scope :today, -> { where(created_at: Time.zone.today.all_day) }
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
      Positions::PaperStatsQuery.call(date: date)
    end

    def paper_positions_details(limit: Positions::PaperPositionsQuery::DEFAULT_LIMIT, offset: 0)
      Positions::PaperPositionsQuery.call(limit: limit, offset: offset)
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
      return Positions::PaperStatsQuery.call(date: date)[:win_rate] if exited.nil?

      return 0.0 if exited.empty?

      winners = exited.count { |tracker| (tracker.last_pnl_rupees || 0).positive? }
      (winners.to_f / exited.size * 100).round(2)
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

    # rubocop:disable Rails/Delegate
    def clear_orphaned_redis_pnl!
      Positions::IndexSync.clear_orphaned_redis_pnl!
    end
    # rubocop:enable Rails/Delegate

    def should_clear_orphaned?
      @last_clear ||= ORPHANED_CLEAR_INTERVAL.ago
      return true if Time.current - @last_clear >= ORPHANED_CLEAR_INTERVAL

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

  def in_profit?
    current_pnl_rupees.to_f.positive?
  end

  # Returns the state machine for this tracker, giving callers a clean
  # capability-based interface (can_trail?, can_request_exit?, etc.) and
  # validated transition helpers without reading raw status strings.
  def state_machine
    Positions::States::PositionStateMachine.new(self)
  end

  def mark_active!(avg_price:, quantity:)
    state_machine.transition_to!(:active)

    avg_price_bd = avg_price.present? ? BigDecimal(avg_price.to_s) : nil
    attrs = {
      status: :active,
      avg_price: avg_price_bd,
      entry_price: entry_price.presence || avg_price_bd,
      quantity: quantity
    }

    update!(attrs.compact)
    subscribe

    return if avg_price_bd.blank?

    Live::RedisPnlCache.instance.store_pnl(
      tracker_id: id,
      pnl: BigDecimal(0),
      pnl_pct: 0.0,
      ltp: avg_price_bd,
      hwm: BigDecimal(0),
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
    Positions::ExitFlow.call(tracker: self, exit_price: exit_price, exited_at: exited_at, exit_reason: exit_reason)
  end

  def tradable
    watchable
  end

  # Get current PnL from Redis cache (preferred) or fallback to DB
  # This avoids frequent DB reads - Redis is the source of truth for active positions
  def current_pnl_rupees
    return last_pnl_rupees if exited? # Exited positions: use DB (final value)

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return BigDecimal(cache[:pnl].to_s) if cache && cache[:pnl]

    last_pnl_rupees || BigDecimal(0)
  rescue Redis::BaseError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    last_pnl_rupees || BigDecimal(0)
  rescue StandardError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    last_pnl_rupees || BigDecimal(0)
  end

  # Get current PnL percentage from Redis cache (preferred) or fallback to DB
  def current_pnl_pct
    return last_pnl_pct if exited? # Exited positions: use DB (final value)

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return BigDecimal(cache[:pnl_pct].to_s) if cache && cache[:pnl_pct]

    last_pnl_pct
  rescue Redis::BaseError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    last_pnl_pct
  rescue StandardError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    last_pnl_pct
  end

  # Get current high water mark from Redis cache (preferred) or fallback to DB
  def current_hwm_pnl
    return high_water_mark_pnl if exited? # Exited positions: use DB (final value)

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return BigDecimal(cache[:hwm_pnl].to_s) if cache && cache[:hwm_pnl]

    high_water_mark_pnl || BigDecimal(0)
  rescue Redis::BaseError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    high_water_mark_pnl || BigDecimal(0)
  rescue StandardError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    high_water_mark_pnl || BigDecimal(0)
  end

  # Get current high water mark percentage from Redis cache (preferred) or fallback to meta
  def current_hwm_pnl_pct
    return BigDecimal(meta_hash['hwm_pnl_pct'].to_s) if exited? && meta_hash['hwm_pnl_pct'].present?

    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return BigDecimal(cache[:hwm_pnl_pct].to_s) if cache && cache[:hwm_pnl_pct]

    BigDecimal(meta_hash['hwm_pnl_pct'].to_s)
  rescue Redis::BaseError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    BigDecimal(meta_hash['hwm_pnl_pct'].to_s)
  rescue StandardError => e
    Rails.logger.error("[PositionTracker] #{e.class} - #{e.message}")
    BigDecimal(meta_hash['hwm_pnl_pct'].to_s)
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
    Positions::MetaUpdater.new(tracker: self).update! do |meta|
      meta['breakeven_locked'] = true
      meta
    end
  end

  def unsubscribe
    Positions::FeedSubscription.unsubscribe(tracker: self)
  end

  def subscribe
    Positions::FeedSubscription.call(tracker: self)
  end

  def alpha_signal_just_exited?
    alpha_source.present? && saved_change_to_status? && exited?
  end

  def record_alpha_outcome!
    if last_pnl_rupees.to_f.positive?
      Risk::LimitsGuard.record_win!
    else
      Risk::LimitsGuard.record_loss!
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
    Positions::IndexSync.new(tracker: self).register
  end

  def subscribe_to_feed
    subscribe
    register_in_index
  end

  def unregister_from_index
    Positions::IndexSync.new(tracker: self).unregister
    unsubscribe
  end

  def cleanup_if_exited
    return unless saved_change_to_status? && exited?

    unregister_from_index
    clear_redis_pnl_cache
  end

  def refresh_index_if_relevant
    Positions::IndexSync.new(tracker: self).refresh_if_relevant
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
      exit_reason: metadata['exit_reason'],
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
      persist_hwm_pnl_pct(cache[:hwm_pnl_pct])
    end

    # CRITICAL: Recalculate pnl_pct from final PnL + entry price, don't use Redis snapshot
    # Redis pnl_pct is a snapshot from exit trigger time, not final realized PnL
    # This ensures last_pnl_pct reflects actual P&L, not stale cache values
    entry_price = BigDecimal((self.entry_price || 0).to_s)
    quantity = (self.quantity || 0).to_i
    pnl_value = BigDecimal((last_pnl_rupees || cache[:pnl] || 0).to_s)

    if entry_price.positive? && quantity.positive?
      self.last_pnl_pct = pnl_value / (entry_price * quantity)
    else
      self.last_pnl_pct = BigDecimal('0')
    end
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

  def segment_must_be_tradable
    return if segment.blank? # Allow blank segments (will be validated elsewhere if needed)

    return if Orders::Placer::VALID_TRADABLE_SEGMENTS.include?(segment.to_s.upcase)

    errors.add(
      :segment,
      "is not tradable. Segment '#{segment}' is an index segment and cannot be traded. " \
      "Valid tradable segments: #{Orders::Placer::VALID_TRADABLE_SEGMENTS.join(', ')}"
    )
  end

  def index_registration_relevant?
    active? && entry_price.present? && quantity.to_i.positive?
  end

  def feed_subscription_relevant?
    Positions::FeedSubscription.segment_key_for(tracker: self).present? && security_id.present?
  end

  def persist_hwm_pnl_pct(value)
    return if value.blank?

    self.meta = meta_hash.merge('hwm_pnl_pct' => value.to_f)
  end
end
