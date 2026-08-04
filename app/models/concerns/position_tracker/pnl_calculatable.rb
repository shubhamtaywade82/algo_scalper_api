# frozen_string_literal: true

class PositionTracker < ApplicationRecord
  module PnlCalculatable
    extend ActiveSupport::Concern

    def in_profit?
      current_pnl_rupees.positive?
    end

    def hydrate_pnl_from_cache!
      cache = Live::RedisPnlCache.instance.fetch_pnl(id)
      return unless cache

      cache_live_pnl(cache[:pnl], pnl_pct: cache[:pnl_pct]) if cache[:pnl]
      self.high_water_mark_pnl = BigDecimal(cache[:hwm_pnl].to_s) if cache[:hwm_pnl]
    rescue StandardError
      nil
    end

    def current_pnl_rupees
      return last_pnl_rupees || zero_bd if exited?

      cache = Live::RedisPnlCache.instance.fetch_pnl(id)
      return BigDecimal(cache[:pnl].to_s) if cache && cache[:pnl]

      last_pnl_rupees || zero_bd
    rescue StandardError => e
      log_pnl_cache_error(e)
      last_pnl_rupees || zero_bd
    end

    def current_pnl_pct
      return last_pnl_pct if exited?

      cache = Live::RedisPnlCache.instance.fetch_pnl(id)
      return BigDecimal(cache[:pnl_pct].to_s) if cache && cache[:pnl_pct]

      last_pnl_pct
    rescue StandardError => e
      log_pnl_cache_error(e)
      last_pnl_pct
    end

    def current_hwm_pnl
      return high_water_mark_pnl || zero_bd if exited?

      cache = Live::RedisPnlCache.instance.fetch_pnl(id)
      return BigDecimal(cache[:hwm_pnl].to_s) if cache && cache[:hwm_pnl]

      high_water_mark_pnl || zero_bd
    rescue StandardError => e
      log_pnl_cache_error(e)
      high_water_mark_pnl || zero_bd
    end

    def current_hwm_pnl_pct
      return BigDecimal(meta_hash['hwm_pnl_pct'].to_s) if exited? && meta_hash['hwm_pnl_pct'].present?

      cache = Live::RedisPnlCache.instance.fetch_pnl(id)
      return BigDecimal(cache[:hwm_pnl_pct].to_s) if cache && cache[:hwm_pnl_pct]

      BigDecimal(meta_hash['hwm_pnl_pct'].to_s)
    rescue StandardError => e
      log_pnl_cache_error(e)
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

    def cache_live_pnl(pnl, pnl_pct: nil)
      pnl_value = BigDecimal(pnl.to_s)
      self.last_pnl_rupees = pnl_value
      self.last_pnl_pct = pnl_pct.nil? ? nil : BigDecimal(pnl_pct.to_s)

      current_hwm = high_water_mark_pnl.present? ? BigDecimal(high_water_mark_pnl.to_s) : BigDecimal(0)
      self.high_water_mark_pnl = [current_hwm, pnl_value].max
    end

    private

    def zero_bd
      BigDecimal(0)
    end

    def log_pnl_cache_error(error)
      Rails.logger.error("[PositionTracker] #{error.class} - #{error.message}")
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

        persist_hwm_pnl_pct(cache[:hwm_pnl_pct])
      end

      recalculate_last_pnl_pct(cache[:pnl])
    end

    def recalculate_last_pnl_pct(cached_pnl)
      entry = BigDecimal((entry_price || 0).to_s)
      qty = (quantity || 0).to_i
      pnl = BigDecimal((last_pnl_rupees || cached_pnl || 0).to_s)

      self.last_pnl_pct = entry.positive? && qty.positive? ? (pnl / (entry * qty)) : BigDecimal('0')
    end

    def persist_hwm_pnl_pct(value)
      return if value.blank?

      self.meta = meta_hash.merge('hwm_pnl_pct' => value.to_f)
    end
  end
end
