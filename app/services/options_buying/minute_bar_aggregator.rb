# frozen_string_literal: true

module OptionsBuying
  # Aggregates live WebSocket ticks into 1-minute OHLCV buckets in Redis.
  #
  # On the first tick for a +security_id+ in a trading session, triggers a
  # 30-minute historical backfill via {Live::HistoricalBackfillService} so that
  # {OptionsBuying::BreakoutEvaluator} and indicator calculations have
  # meaningful history immediately (rather than starting from zero).
  class MinuteBarAggregator
    # Session-scoped set of security_ids already seen today.
    # Cleared automatically at midnight so warm-up fires once per day per strike.
    @seen_security_ids = Set.new
    @seen_date = nil

    class << self
      attr_accessor :seen_security_ids, :seen_date

      def record_tick!(tick)
        new(tick).record_tick!
      end

      # Reset the session set — called on daemon restart or new trading day.
      def reset_session!
        @seen_security_ids = Set.new
        @seen_date = Date.current
      end
    end

    def initialize(tick)
      @tick = tick
    end

    def record_tick!
      MinuteBarAggregator.reset_session! if MinuteBarAggregator.seen_date != Date.current

      security_id = @tick[:security_id].to_s
      return if security_id.blank?

      ltp = @tick[:ltp].to_f
      return unless ltp.positive?

      warmup_new_instrument(security_id) unless MinuteBarAggregator.seen_security_ids.include?(security_id)
      MinuteBarAggregator.seen_security_ids.add(security_id)

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

    # Backfill the last 30 minutes of 1-min candles the first time we see a
    # security_id this session. Errors are rescued so a backfill failure never
    # interrupts the live tick path.
    def warmup_new_instrument(security_id)
      segment = @tick[:segment] || @tick[:exchange_segment]
      instrument = if segment
                     Instrument.find_by_sid_and_segment(security_id: security_id, segment_code: segment)
                   else
                     Instrument.find_by(security_id: security_id)
                   end
      return unless instrument

      from_date = 30.minutes.ago.strftime("%Y-%m-%d %H:%M:%S")
      Live::HistoricalBackfillService.new.backfill(
        instrument: instrument,
        interval: 1,
        from_date: from_date,
        reason: :warmup
      )
    rescue StandardError => e
      Rails.logger.warn(
        "[MinuteBarAggregator] Warmup backfill failed for security_id=#{security_id}: " \
        "#{e.class} - #{e.message}"
      )
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
