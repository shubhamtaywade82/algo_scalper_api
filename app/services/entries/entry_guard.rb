# frozen_string_literal: true

require_relative '../concerns/broker_fee_calculator'
require_relative 'bos_extractor'

module Entries
  class EntryGuard
    ENTRY_CONTRACT = 'bos_machine_v1'
    SUPERTREND_CONTRACT = 'supertrend_machine_v1'

    class << self
      include Live::UnderlyingLtpResolver

      def entry_guard_pipeline
        @entry_guard_pipeline ||= EntryGuardPipeline.new
      end

      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil, signal: nil)
        # 1. Pipeline Execution
        context = {
          index_cfg: index_cfg,
          pick: pick,
          direction: direction,
          scale_multiplier: scale_multiplier,
          entry_metadata: entry_metadata || {},
          permission: permission,
          is_paper: entry_metadata&.dig(:paper) || Rails.env.local?
        }

        result = entry_guard_pipeline.run(context)
        if result != EntryGuardPipeline::PASS
          reason = result.is_a?(Hash) ? result[:blocked] : result.to_s
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              reason: reason
            }
          )
          signal&.record_entry_outcome('blocked', reason)
          return false
        end

        # 2. Order Execution
        execution_result = OrderExecutionService.call(context)

        if execution_result.is_a?(Hash) && execution_result[:error]
          signal&.record_entry_outcome('blocked', execution_result[:error])
          return false
        end

        # Success - Tracker created
        signal&.record_entry_outcome('entered')
        true
      rescue StandardError => e
        signal&.record_entry_outcome('blocked', "exception: #{e.class}")
        bt = e.backtrace&.first(12)&.join("\n")
        msg = "EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}"
        msg = "#{msg}\n#{bt}" if bt.present?
        Rails.logger.error(msg)
        false
      end

      # Used by OrderExecutionService
      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata:, bos_context:)
        meta_hash = build_base_meta(index_cfg: index_cfg, pick: pick, direction: bos_context&.dig(:direction))
        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        PositionTracker.create!(
          order_no: order_no,
          instrument: instrument,
          watchable: instrument,
          symbol: pick[:symbol],
          security_id: pick[:security_id],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: :active,
          paper: false,
          meta: meta_hash
        )
      end

      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:, order_no:, entry_metadata:, bos_context:)
        meta_hash = build_base_meta(index_cfg: index_cfg, pick: pick, direction: bos_context&.dig(:direction))
        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)

        PositionTracker.create!(
          order_no: order_no,
          instrument: instrument,
          watchable: instrument,
          symbol: pick[:symbol],
          security_id: pick[:security_id],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: :active,
          paper: true,
          meta: meta_hash
        )
      end

      def build_client_order_id(index_cfg:, pick:)
        "#{index_cfg[:key]}_#{pick[:symbol]}_#{Time.current.to_i}"
      end

      def find_instrument(index_cfg)
        Instrument.find_by(security_id: index_cfg[:sid], segment: index_cfg[:segment])
      end

      def cooldown_active_for_index?(index_key, cooldown)
        return false if index_key.blank? || cooldown <= 0

        last = Rails.cache.read("reentry:index:#{index_key}")
        last.present? && (Time.current - last) < cooldown
      end

      # BANKNIFTY trades only in the last week before monthly expiry.
      # Uses instrument expiry_list to find the actual monthly expiry date (holiday-aware).
      # Falls back to last-Thursday-of-month calculation only when expiry_list is unavailable.
      # Returns true if today is within 7 calendar days of the nearest upcoming monthly expiry.
      def banknifty_last_week?(instrument: nil)
        today          = Time.zone.today
        monthly_expiry = banknifty_monthly_expiry(instrument, today)
        return false unless monthly_expiry

        days_to_expiry = (monthly_expiry - today).to_i
        days_to_expiry.between?(0, 6)
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] banknifty_last_week? error: #{e.message}")
        false
      end

      def extract_order_no(response)
        return response[:order_id] || response['order_id'] if response.is_a?(Hash)
        response
      end

      def timeframe_to_interval(timeframe)
        return nil if timeframe.blank?
        str = timeframe.to_s.strip.downcase
        return nil if str.empty?
        if str.end_with?('h')
          hours = str.gsub(/[^0-9]/, '').to_i
          return nil if hours <= 0
          return hours * 60
        end
        str.gsub(/[^0-9]/, '').to_i
      end

      private

      def banknifty_monthly_expiry(instrument, today)
        expiry_list = instrument&.expiry_list&.compact
        if expiry_list.present?
          parsed = expiry_list.filter_map do |raw|
            case raw
            when Date then raw
            when String then Date.parse(raw) rescue nil
            when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
            end
          end.sort

          monthly_expiries = parsed
            .group_by { |d| [d.year, d.month] }
            .map { |_, dates| dates.max }
            .sort

          nearest = monthly_expiries.find { |d| d >= today }
          return nearest if nearest
        end

        # Fallback: last Thursday of month
        last_day = today.end_of_month
        last_thu = last_day - ((last_day.wday - 4) % 7).days
        if last_thu < today
          last_day = (today + 1.month).end_of_month
          last_thu = last_day - ((last_day.wday - 4) % 7).days
        end
        last_thu
      end

      def build_base_meta(index_cfg:, pick:, direction:)
        {
          index_key: index_cfg[:key].to_s,
          symbol: pick[:symbol].to_s,
          direction: direction || pick[:direction],
          entry_at: Time.current.iso8601
        }
      end

      def apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price:, quantity:)
        # Simplification: logic moved partially to service, but meta building kept here for now
        # Call the existing implementation or refactor it into a dedicated MetaBuilder
        Entries::MetaBuilder.call(meta_hash, bos_context, entry_metadata, entry_price: entry_price, quantity: quantity)
      end
    end
  end
end
