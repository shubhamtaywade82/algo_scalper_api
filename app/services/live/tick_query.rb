# frozen_string_literal: true

module Live
  class TickQuery
    NO_LTP_LOG_COOLDOWN = 30.seconds
    CACHE_ERROR_LOG_COOLDOWN = 30.seconds

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
          log_once(
            cache_key: "tick_query:no_ltp:#{segment}:#{security_id}",
            cooldown: NO_LTP_LOG_COOLDOWN,
            level: :warn,
            message: "[TickQuery] no LTP in cache for #{segment}/#{security_id}"
          )
          return nil
        end

        tick_ts = resolve_tick_timestamp(tick_data)
        MarketTick.new(
          segment: segment,
          security_id: security_id,
          ltp: BigDecimal(raw_ltp.to_s),
          timestamp: tick_ts,
          oi: tick_data&.dig(:oi).to_i,
          oi_change: tick_data&.dig(:oi_change).to_i,
          bid: tick_data&.dig(:bid)&.to_f,
          ask: tick_data&.dig(:ask)&.to_f,
          bid_qty: (tick_data&.dig(:bid_qty) || tick_data&.dig(:bid_quantity)).to_i,
          ask_qty: (tick_data&.dig(:ask_qty) || tick_data&.dig(:ask_quantity)).to_i,
          volume: (tick_data&.dig(:volume) || tick_data&.dig(:vol)).to_i,
          prev_close: tick_data&.dig(:prev_close)&.to_f
        )
      rescue StandardError => e
        log_once(
          cache_key: "tick_query:cache_error:#{segment}:#{security_id}",
          cooldown: CACHE_ERROR_LOG_COOLDOWN,
          level: :warn,
          message: "[TickQuery] cache miss for #{segment}/#{security_id}: #{e.message}"
        )
        nil
      end

      def ltp_for(tracker)
        self.for(tracker)&.ltp
      end

      private

      def log_once(cache_key:, cooldown:, level:, message:)
        return unless Rails.cache
        return if Rails.cache.read(cache_key)

        Rails.logger.public_send(level, message)
        Rails.cache.write(cache_key, true, expires_in: cooldown)
      rescue StandardError
        Rails.logger.public_send(level, message)
      end

      # WebSocket ticks store timestamp under :ts (exchange epoch seconds from DhanHQ decoder),
      # while REST/refresh services store under :timestamp.  Resolve whichever is available
      # so that freshness checks in LtpResolutionGuard and downstream consumers work correctly.
      def resolve_tick_timestamp(tick_data)
        raw = tick_data&.dig(:timestamp) || tick_data&.dig(:ts)
        return Time.current unless raw

        if raw.is_a?(Numeric)
          Time.at(raw.to_f)
        elsif raw.respond_to?(:to_time)
          raw.to_time
        else
          Time.current
        end
      rescue StandardError
        Time.current
      end
    end
  end
end
