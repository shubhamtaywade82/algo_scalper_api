# frozen_string_literal: true

module Entries
  module Guards
    # Blocks entries before per-index or global earliest_entry_time (IST).
    class EarliestEntryGuard
      include BaseGuard

      DEFAULT_EARLIEST = '09:45'

      def self.call(context)
        index_cfg = context[:index_cfg] || {}
        earliest = earliest_entry_time(index_cfg)
        return PASS if earliest.blank?

        now_hhmm = Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
        return PASS if now_hhmm >= earliest.to_s

        key = index_cfg[:key] || 'index'
        { blocked: "earliest entry time not reached for #{key} (#{earliest} IST)" }
      rescue StandardError => e
        Rails.logger.warn("[EarliestEntryGuard] #{e.class} - #{e.message}")
        PASS
      end

      def self.earliest_entry_time(index_cfg)
        index_cfg.dig(:execution, :earliest_entry_time).presence ||
          AlgoConfig.fetch.dig(:risk, :time_overrides, :earliest_entry_time).presence ||
          DEFAULT_EARLIEST
      rescue StandardError
        DEFAULT_EARLIEST
      end
    end
  end
end
