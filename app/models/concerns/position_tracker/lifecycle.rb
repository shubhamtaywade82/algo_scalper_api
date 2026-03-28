# frozen_string_literal: true

class PositionTracker < ApplicationRecord
  module Lifecycle
    extend ActiveSupport::Concern

    included do
      after_commit :clear_redis_pnl_cache, on: :destroy
      after_update_commit :cleanup_if_exited
      after_update_commit :analyze_trade_if_exited
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
      initialize_extremes_in_meta
      subscribe
      broadcast_position_activated

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
      state_machine.transition_to!(:cancelled)
      update!(status: :cancelled)
    end

    def mark_exited!(exit_price: nil, exited_at: nil, exit_reason: nil)
      Positions::ExitFlow.call(tracker: self, exit_price: exit_price, exited_at: exited_at, exit_reason: exit_reason)
    end

    private

    def analyze_trade_if_exited
      return unless saved_change_to_status? && exited?

      Optimization::TradeAnalyzer.call(self)
    end

    def cleanup_if_exited
      return unless saved_change_to_status? && exited?

      unregister_from_index
      clear_redis_pnl_cache
    end

    def clear_redis_pnl_cache
      Live::RedisPnlCache.instance.clear_tracker(id)
    end

    def initialize_extremes_in_meta
      return if entry_price.blank?

      meta = meta_hash.dup
      meta['highest_price'] ||= entry_price.to_f
      meta['lowest_price'] ||= entry_price.to_f
      update!(meta: meta) if meta != meta_hash
    rescue StandardError => e
      Rails.logger.debug("[PositionTracker] initialize_extremes_in_meta failed for #{order_no}: #{e.class} - #{e.message}")
    end
  end
end
