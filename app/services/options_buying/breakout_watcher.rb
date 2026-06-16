# frozen_string_literal: true

module OptionsBuying
  class BreakoutWatcher
    # Compression-arm is a slow-moving daily condition; recomputing the ATR ratio
    # on every tick is wasteful. Re-check at most once per this many seconds/index.
    COMPRESSION_CHECK_INTERVAL = 60
    DEFAULT_SUBSCRIBE_SYNC_SECONDS = 30

    def initialize(hub: Live::MarketFeedHub.instance)
      @hub = hub
      @running = false
      @last_compression_check = {}
      @sync_thread = nil
    end

    def start
      @running = true
      unless feature_enabled?
        Rails.logger.info('[OptionsBuying::BreakoutWatcher] Disabled (options_buying.breakout.enabled=false)')
        return
      end

      @hub.on_tick { |tick| handle_tick(tick) }
      start_subscription_sync!
      Rails.logger.info('[OptionsBuying::BreakoutWatcher] on_tick callback registered')
    end

    def stop
      @running = false
      if @sync_thread
        @sync_thread.join(2) if @sync_thread.alive?
        @sync_thread = nil
      end
      Rails.logger.info('[OptionsBuying::BreakoutWatcher] Stopped')
    end

    private

    def feature_enabled?
      Mode.breakout_enabled?
    end

    # ChainRadarJob runs in the Solid Queue worker process and only writes radar
    # strikes to Redis; the live WebSocket hub lives in *this* daemon process. So
    # we poll the shared radar set here and subscribe the strikes to the feed,
    # otherwise option ticks never flow and the breakout path can't arm.
    def start_subscription_sync!
      @sync_thread = Thread.new do
        Thread.current.name = 'options-buying-radar-subscribe'
        sync_radar_subscriptions! # initial pass so we don't wait a full interval
        while @running
          sleep(subscribe_sync_seconds)
          break unless @running

          sync_radar_subscriptions!
        end
      end
    end

    def sync_radar_subscriptions!
      return unless @running && feature_enabled?

      targets = IndexConfigLoader.load_indices.flat_map do |idx|
        StateStore.radar_strikes(idx[:key]).filter_map do |strike|
          sid = strike[:security_id].to_s
          segment = strike[:segment].to_s
          next if sid.blank? || segment.blank?
          next if @hub.subscribed?(segment: segment, security_id: sid)

          { segment: segment, security_id: sid }
        end
      end
      return if targets.empty?

      @hub.subscribe_many(targets)
      Rails.logger.info("[OptionsBuying::BreakoutWatcher] Subscribed #{targets.size} radar strike(s) to feed")
    rescue StandardError => e
      Rails.logger.warn("[OptionsBuying::BreakoutWatcher] subscription sync #{e.class} - #{e.message}")
    end

    def subscribe_sync_seconds
      (Mode.config.dig(:chain_radar, :subscribe_sync_seconds) || DEFAULT_SUBSCRIBE_SYNC_SECONDS).to_i
    end

    def handle_tick(tick)
      return unless @running
      return unless feature_enabled?

      OptionsBuying::StreamWriter.record!(tick)
      OptionsBuying::MinuteBarAggregator.record_tick!(tick) unless OptionsBuying::Mode.streams_enabled?
      update_compression_arm(tick)
    rescue StandardError => e
      Rails.logger.warn("[OptionsBuying::BreakoutWatcher] #{e.class} - #{e.message}")
    end

    def update_compression_arm(tick)
      return unless Mode.compression_enabled?
      return unless Mode.config.dig(:breakout, :compression_arm) == true

      return unless compression_check_due?(tick[:security_id].to_s)

      index_key = index_key_for_tick(tick)
      return unless index_key

      instrument = instrument_for_index(index_key)
      return unless instrument
      return unless OptionsBuying::ATRCompressionChecker.compressed?(instrument)

      StateStore.set_compression_arm!(index_key)
    end

    def compression_check_due?(security_id)
      return false if security_id.blank?

      now = Time.current.to_i
      last = @last_compression_check[security_id]
      return false if last && (now - last) < COMPRESSION_CHECK_INTERVAL

      @last_compression_check[security_id] = now
      true
    end

    def index_key_for_tick(tick)
      sid = tick[:security_id].to_s
      idx = IndexConfigLoader.load_indices.find { |c| c[:sid].to_s == sid }
      return idx[:key] if idx

      IndexConfigLoader.load_indices.each do |entry|
        return entry[:key] if StateStore.radar_strikes(entry[:key]).any? { |s| s[:security_id].to_s == sid }
      end
      nil
    end

    def instrument_for_index(index_key)
      idx = IndexConfigLoader.load_indices.find { |c| c[:key].to_s == index_key.to_s }
      return unless idx

      Instrument.find_by(security_id: idx[:sid].to_s, exchange_segment: idx[:segment])
    end
  end
end
