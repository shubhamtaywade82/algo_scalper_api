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

    def cleanup_exit_caches
      Live::PositionIndex.instance.remove(id, security_id)
      Live::RedisPnlCache.instance.clear_tracker(id)
      Live::RedisTickCache.instance.clear_tick(segment, security_id)
      Live::TickCache.delete(segment, security_id)
    end

    def prepare_exit_metadata(exit_reason)
      exit_reason ||= meta.is_a?(Hash) ? meta['exit_reason'] : nil
      metadata = meta.is_a?(Hash) ? meta.dup : {}
      metadata['exit_reason'] = exit_reason if exit_reason.present?
      metadata['exit_triggered_at'] ||= Time.current
      metadata
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

    def fetch_ltp_from_cache
      seg = segment.presence || watchable&.exchange_segment || instrument&.exchange_segment
      tick = Live::TickQuery.for_security(segment: seg, security_id: security_id)
      tick&.ltp
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

    def register_cooldown!
      return if symbol.blank?

      Rails.cache.write("reentry:#{symbol}", Time.current, expires_in: 8.hours)

      idx_key = meta&.dig('index_key')
      return if idx_key.blank?

      Rails.cache.write("reentry:index:#{idx_key}", Time.current, expires_in: 8.hours)
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
