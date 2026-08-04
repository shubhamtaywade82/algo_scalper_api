# frozen_string_literal: true

module Live
  class TickQuery
    class << self
      def for(tracker)
        return nil unless tracker

        segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
        for_security(segment: segment, security_id: tracker.security_id)
      end

      def for_security(segment:, security_id:)
        return nil if segment.blank? || security_id.blank?

        tick_data = Live::TickCache.fetch(segment, security_id)
        raw_ltp = tick_data&.dig(:ltp) || Live::TickCache.ltp(segment, security_id)
        unless raw_ltp
          Rails.logger.warn("[TickQuery] no LTP in cache for #{segment}/#{security_id}")
          return nil
        end

        MarketTick.new(
          segment: segment,
          security_id: security_id,
          ltp: BigDecimal(raw_ltp.to_s),
          timestamp: tick_data&.dig(:timestamp) || Time.current,
          oi: tick_data&.dig(:oi).to_i,
          oi_change: tick_data&.dig(:oi_change).to_i,
          bid: tick_data&.dig(:bid)&.to_f,
          ask: tick_data&.dig(:ask)&.to_f,
          volume: tick_data&.dig(:volume).to_i,
          prev_close: tick_data&.dig(:prev_close)&.to_f
        )
      rescue StandardError => e
        Rails.logger.warn("[TickQuery] cache miss for #{segment}/#{security_id}: #{e.message}")
        nil
      end

      def ltp_for(tracker)
        self.for(tracker)&.ltp
      end
    end
  end
end
