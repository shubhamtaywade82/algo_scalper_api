# frozen_string_literal: true

module OptionsBuying
  class StreamWriter
    def self.record!(tick)
      new(tick).record!
    end

    def initialize(tick)
      @tick = tick
    end

    def record!
      return unless Mode.streams_enabled?

      security_id = @tick[:security_id].to_s
      return if security_id.blank?

      ltp = @tick[:ltp].to_f
      return unless ltp.positive?

      ts = tick_timestamp
      payload = {
        ltp: ltp,
        oi: @tick[:oi].to_i,
        volume: @tick[:volume].to_i,
        vol: @tick[:volume].to_i,
        ts: ts,
        bucket: ts - (ts % 60)
      }

      StateStore.xadd_tick(security_id, payload)
      StateStore.cache_tick_snapshot(security_id, payload)
      StateStore.track_monitored_strike(security_id)
      append_legacy_bucket(security_id, payload) unless stream_only?
      payload
    rescue StandardError => e
      Rails.logger.warn("[StreamWriter] #{e.class} - #{e.message}")
      nil
    end

    private

    def stream_only?
      Mode.config.dig(:streams, :legacy_zset_enabled) == false
    end

    def append_legacy_bucket(security_id, payload)
      StateStore.append_minute_tick(security_id, payload[:bucket], payload)
    end

    def tick_timestamp
      raw = @tick[:timestamp] || @tick[:ts]
      return raw.to_i if raw

      Time.current.to_i
    end
  end
end
