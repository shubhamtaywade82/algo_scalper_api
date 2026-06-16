# frozen_string_literal: true

module OptionsBuying
  class MinuteBarAggregator
    def self.record_tick!(tick)
      new(tick).record_tick!
    end

    def initialize(tick)
      @tick = tick
    end

    def record_tick!
      security_id = @tick[:security_id].to_s
      return if security_id.blank?

      ltp = @tick[:ltp].to_f
      return unless ltp.positive?

      ts = tick_timestamp
      bucket = ts - (ts % 60)

      StateStore.append_minute_tick(security_id, bucket, {
        ts: ts,
        ltp: ltp,
        oi: @tick[:oi].to_i,
        vol: @tick[:volume].to_i
      })

      evaluate_completed_bucket(security_id, bucket - 60) if ts % 60 >= 55
    end

    private

    def tick_timestamp
      raw = @tick[:timestamp] || @tick[:ts]
      return raw.to_i if raw

      Time.current.to_i
    end

    def evaluate_completed_bucket(security_id, bucket)
      return if bucket <= 0

      index_key = index_key_for_security(security_id)
      return unless index_key

      OptionsBuying::BreakoutEvaluator.evaluate!(
        index_key: index_key,
        security_id: security_id,
        bucket: bucket
      )
    end

    def index_key_for_security(security_id)
      IndexConfigLoader.load_indices.each do |idx|
        strikes = StateStore.radar_strikes(idx[:key])
        return idx[:key] if strikes.any? { |s| s[:security_id].to_s == security_id.to_s }
      end
      nil
    end
  end
end
