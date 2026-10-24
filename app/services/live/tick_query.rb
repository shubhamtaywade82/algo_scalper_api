# frozen_string_literal: true

module Live
  class TickQuery
    class << self
      # Tick for a tracked position.
      #
      # Segment resolution (error-handling review 2026-09): the consolidated
      # Instrument is the single authoritative source of the broker segment.
      # The previous chain (tracker.segment || watchable&.exchange_segment ||
      # instrument&.exchange_segment) silently traded on "whichever source
      # happened to be available". Now:
      #
      #   * tracker.instrument is the traded contract -> its exchange_segment wins
      #   * legacy rows without an instrument link -> tracker.segment
      #   * both present and disagreeing -> Errors::InvariantViolation (corrupt row)
      #   * neither present -> nil (documented: no authoritative segment)
      #
      # @return [MarketTick, nil] nil when the tracker has no authoritative
      #   segment or no tick is cached for it
      def for(tracker)
        return nil unless tracker

        segment = authoritative_segment_for(tracker)
        if segment.blank?
          Rails.logger.warn("[TickQuery] no authoritative segment for tracker=#{tracker.id} security_id=#{tracker.security_id}")
          return nil
        end

        for_security(segment: segment, security_id: tracker.security_id)
      end

      # @return [MarketTick, nil] nil when no LTP is cached (documented domain
      #   outcome — the feed has simply not delivered a tick)
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
          # Honest timestamps (review finding): never fabricate Time.current.
          # Raw WS ticks carry no :timestamp key; :cached_at is the real
          # last-write time set by TickCache#put on every genuine tick. If
          # neither is present the tick is :invalid by MarketTick#freshness —
          # previously it silently looked fresh forever.
          timestamp: tick_data&.dig(:timestamp) || tick_data&.dig(:cached_at),
          oi: tick_data&.dig(:oi).to_i,
          oi_change: tick_data&.dig(:oi_change).to_i,
          bid: tick_data&.dig(:bid)&.to_f,
          ask: tick_data&.dig(:ask)&.to_f,
          volume: tick_data&.dig(:volume).to_i,
          prev_close: tick_data&.dig(:prev_close)&.to_f
        )
      end

      def ltp_for(tracker)
        self.for(tracker)&.ltp
      end

      private

      # @return [String, nil]
      # @raise [Errors::InvariantViolation] when tracker and its instrument disagree
      def authoritative_segment_for(tracker)
        instrument = tracker.instrument
        return tracker.segment.presence if instrument.nil?

        # The instrument FK must reference the traded contract — if it points
        # at a different security the row is corrupt and its segment cannot
        # be trusted either; fall back to the stored pair and log loudly.
        unless instrument.security_id.to_s == tracker.security_id.to_s
          Rails.logger.error(
            "[TickQuery] tracker=#{tracker.id} security_id=#{tracker.security_id} " \
            "references instrument=#{instrument.id} security_id=#{instrument.security_id} — mismatch"
          )
          return tracker.segment.presence
        end

        canonical = instrument.exchange_segment.presence
        stored = tracker.segment.presence
        if canonical && stored && canonical != stored
          raise Errors::InvariantViolation,
                "tracker=#{tracker.id} segment #{stored.inspect} disagrees with instrument=#{instrument.id} " \
                "exchange_segment #{canonical.inspect}"
        end

        canonical || stored
      end
    end
  end
end
