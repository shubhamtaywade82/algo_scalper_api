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
        return nil unless raw_ltp

        MarketTick.new(
          segment: segment,
          security_id: security_id,
          ltp: BigDecimal(raw_ltp.to_s),
          timestamp: tick_data&.dig(:timestamp) || Time.current
        )
      rescue StandardError
        nil
      end

      def ltp_for(tracker)
        self.for(tracker)&.ltp
      end
    end
  end
end
