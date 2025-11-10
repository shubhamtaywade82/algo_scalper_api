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

  belongs_to :instrument # Kept for backward compatibility during transition
  belongs_to :watchable, polymorphic: true

  store_accessor :meta, :breakeven_locked, :trailing_stop_price, :index_key, :direction

  validates :order_no, presence: true, uniqueness: true
  validates :security_id, presence: true
  validates :status, inclusion: { in: STATUSES.values }

  after_destroy_commit :clear_redis_pnl_cache
  after_update_commit :clear_redis_cache_if_exited

  scope :active, -> { where(status: STATUSES[:active]) }
  scope :pending, -> { where(status: STATUSES[:pending]) }
  scope :paper, -> { where(paper: true) }
  scope :live, -> { where(paper: false) }
  scope :exited_paper, -> { where(paper: true, status: STATUSES[:exited]) }

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

    # Initialize PnL in Redis (will be 0 initially since entry_price = avg_price)
    # This ensures the position is tracked in Redis from the start
    return unless price.present?

    initial_pnl = BigDecimal(0)
    Live::RedisPnlCache.instance.store_pnl(
      tracker_id: id,
      pnl: initial_pnl,
      pnl_pct: 0.0,
      ltp: price,
      hwm: initial_pnl,
      timestamp: Time.current
    )
  end

  def mark_cancelled!
    update!(status: STATUSES[:cancelled])
  end

  def mark_exited!(exit_price: nil, exited_at: nil)
    # Rails.logger.info("[PositionTracker] Exiting position #{order_no} - releasing capital and unsubscribing")

    # Unsubscribe from market feed
    unsubscribe

    # Ensure we have the latest PnL from Redis before persisting
    persist_final_pnl_from_cache

    # Update status and persist final PnL details in a single write
    attrs = {
      last_pnl_rupees: last_pnl_rupees,
      last_pnl_pct: last_pnl_pct,
      high_water_mark_pnl: high_water_mark_pnl
    }.compact

    # Store exit price and timestamp if provided
    attrs[:exit_price] = BigDecimal(exit_price.to_s) if exit_price.present?
    attrs[:exited_at] = exited_at || Time.current

    attrs[:status] = STATUSES[:exited]
    update!(attrs)

    # Clear Redis cache now that data is persisted
    Live::RedisPnlCache.instance.clear_tracker(id)

    # Register cooldown to prevent immediate re-entry
    register_cooldown!

    # Rails.logger.info("[PositionTracker] Position #{order_no} successfully exited and capital released")
  end

  def cache_live_pnl(pnl, pnl_pct: nil)
    pnl_value = BigDecimal(pnl.to_s)
    self.last_pnl_rupees = pnl_value

    self.last_pnl_pct = pnl_pct.nil? ? nil : BigDecimal(pnl_pct.to_s)

    current_hwm = high_water_mark_pnl.present? ? BigDecimal(high_water_mark_pnl.to_s) : BigDecimal(0)
    self.high_water_mark_pnl = [current_hwm, pnl_value].max
  end

  def hydrate_pnl_from_cache!
    cache = Live::RedisPnlCache.instance.fetch_pnl(id)
    return unless cache

    cache_live_pnl(cache[:pnl], pnl_pct: cache[:pnl_pct]) if cache[:pnl]

    self.high_water_mark_pnl = BigDecimal(cache[:hwm_pnl].to_s) if cache[:hwm_pnl]
  rescue StandardError
    nil
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
    segment_key = segment.presence || watchable&.exchange_segment || instrument&.exchange_segment
    return unless segment_key && security_id

    # Rails.logger.debug { "[PositionTracker] Unsubscribing from market feed: #{segment_key}:#{security_id}" }
    Live::MarketFeedHub.instance.unsubscribe(segment: segment_key, security_id: security_id)

    # Also unsubscribe the underlying instrument if it's an option (derivative)
    underlying = if watchable.is_a?(Derivative)
                   watchable.instrument
                 elsif instrument&.underlying_symbol
                   Instrument.find_by(
                     symbol_name: instrument.underlying_symbol,
                     exchange: instrument.exchange,
                     segment: instrument.segment
                   )
                 end
    return unless underlying

    underlying_segment = underlying.exchange_segment
    return unless underlying_segment.present? && underlying.security_id.present?

    Rails.logger.debug do
      "[PositionTracker] Unsubscribing from underlying: #{underlying.symbol_name} " \
        "(#{underlying_segment}:#{underlying.security_id})"
    end
    Live::MarketFeedHub.instance.unsubscribe(
      segment: underlying_segment,
      security_id: underlying.security_id
    )
  end

  def subscribe
    segment_key = segment.presence || watchable&.exchange_segment || instrument&.exchange_segment
    return unless segment_key && security_id

    hub = Live::MarketFeedHub.instance
    # Ensure hub is running (will start if not running)
    hub.start! unless hub.running?

    hub.subscribe(segment: segment_key, security_id: security_id)
  rescue StandardError => e
    Rails.logger.error("[PositionTracker] Failed to subscribe #{order_no}: #{e.message}")
    nil
  end

  # Paper Trading Methods (must be public for EntryGuard to call)

  def paper?
    paper == true
  end

  def live?
    !paper?
  end

  # Helper method to get the actual tradable object (derivative or instrument)
  # Must be public as it's used by EntryGuard and RiskManagerService
  def tradable
    watchable
  end

  # Helper method to get the underlying instrument (for derivatives, get the instrument; for instruments, get itself)
  # Must be public as it's used by EntryGuard for exposure checks
  def underlying_instrument
    if watchable.is_a?(Derivative)
      watchable.instrument
    elsif watchable.is_a?(Instrument)
      watchable
    else
      instrument
    end
  end

  private

  def register_cooldown!
    return if symbol.blank?

    Rails.cache.write("reentry:#{symbol}", Time.current, expires_in: 8.hours)
  end

  def clear_redis_cache_if_exited
    return unless saved_change_to_status? && status == STATUSES[:exited]

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
      self.high_water_mark_pnl = [current_hwm, pnl_value].max
    end

    self.last_pnl_pct = cache[:pnl_pct] ? BigDecimal(cache[:pnl_pct].to_s) : nil
  end

  def meta_hash
    value = self[:meta]
    value.is_a?(Hash) ? value : {}
  end

  # Calculate PnL for paper positions
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

  # Class methods for paper trading statistics
  class << self
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

      # Calculate unrealized PnL from active positions
      unrealized_pnl = active.sum do |tracker|
        tracker.last_pnl_rupees || BigDecimal(0)
      end.to_f

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
      cache = Live::RedisPnlCache.instance
      existing_ids = PositionTracker.pluck(:id).map(&:to_s)
      existing_lookup = existing_ids.each_with_object({}) { |id, hash| hash[id] = true }

      cache.each_tracker_key do |_key, tracker_id|
        next if existing_lookup.key?(tracker_id)

        Rails.logger.warn("[PositionTracker] Clearing orphaned Redis PnL cache for tracker #{tracker_id}")
        cache.clear_tracker(tracker_id)
      end
    end
  end
end
