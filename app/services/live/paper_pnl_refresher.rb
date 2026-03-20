# frozen_string_literal: true

module Live
  class PaperPnlRefresher
    REFRESH_INTERVAL = (AlgoConfig.fetch.dig(:paper_trading, :realtime_interval_seconds) || 1).to_i # seconds
    LTP_RATE_LIMIT_COOLDOWN = 20.seconds

    def initialize
      @thread = nil
      @running = false
      @lock = Mutex.new
      @sleep_mutex = Mutex.new
      @sleep_cv = ConditionVariable.new
      @subscriptions = []
      @last_db_sync = {}
    end

    def start
      @lock.synchronize do
        return if @running

        @running = true
        subscribe_to_position_events
        @thread = Thread.new { run_loop }
      end
    end

    def stop
      @lock.synchronize do
        @running = false
        @thread&.kill
        @thread&.join(1)
        @thread = nil
        unsubscribe_from_position_events
        wake_up!
      end
    end

    private

    def run_loop
      Thread.current.name = 'paper-pnl-refresher'

      loop do
        break unless @running

        begin
          # Skip refresh if market is closed and no active positions
          if TradingSession::Service.market_closed?
            active_count = PositionTracker.paper.active.count
            if active_count.zero?
              # Market closed and no active positions - sleep longer
              sleep 60 # Check every minute when market is closed and no positions
              next
            end
            # Market closed but positions exist - continue refresh (needed for PnL updates)
          end

          if demand_driven_enabled? && Positions::ActiveCache.instance.empty?
            wait_for_interval(idle_interval_seconds)
            next
          end

          refresh_all
        rescue StandardError => e
          Rails.logger.error("[PaperPnlRefresher] ERROR in run_loop: #{e.class} - #{e.message}")
        end
        wait_for_interval(active_interval_seconds)
      end
    rescue StandardError => e
      Rails.logger.error("[PaperPnlRefresher] FATAL ERROR: #{e.class} - #{e.message}")
      @running = false
    end

    def refresh_all
      # Use cached trackers to avoid hitting the DB every second for the active list
      trackers = Positions::ActivePositionsCache.instance.active_trackers.select(&:paper?)

      trackers.each do |t|
        refresh_tracker(t)
      end
    end

    def refresh_tracker(tracker)
      seg = tracker.segment || tracker.watchable&.exchange_segment
      sid = tracker.security_id

      return if seg.blank? || sid.blank?

      ltp = Live::TickQuery.for_security(segment: seg, security_id: sid)&.ltp
      ltp ||= fetch_and_cache_fallback_ltp(tracker, segment: seg, security_id: sid)
      return if ltp.blank?

      entry = BigDecimal(tracker.entry_price.to_s)
      qty   = tracker.quantity.to_i
      gross_pnl = (ltp.to_d - entry) * qty.to_d

      # Deduct broker fees (₹20 per order, ₹40 per trade if exited)
      pnl = BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: tracker.exited?)

      # Calculate decimal (e.g. 0.05 for 5%)
      pct = entry.positive? ? ((ltp.to_d - entry) / entry) : 0

      hwm_pnl = [tracker.high_water_mark_pnl.to_d, pnl].max
      hwm_pnl_pct = entry.positive? ? (hwm_pnl / (entry * qty)) : 0

      # Throttle DB updates: only update DB every 30 seconds OR if PnL changed by > 5% milestone
      last_sync = @last_db_sync[tracker.id]
      pnl_milestone = (tracker.last_pnl_pct.to_f - pct.to_f).abs > 0.05

      if last_sync.nil? || (Time.current - last_sync) > 30.seconds || pnl_milestone
        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pct ? BigDecimal(pct.to_s) : nil,
          high_water_mark_pnl: hwm_pnl
        )
        @last_db_sync[tracker.id] = Time.current
      end

      Live::RedisPnlCache.instance.store_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pct.to_f,
        ltp: ltp,
        hwm: hwm_pnl,
        hwm_pnl_pct: hwm_pnl_pct.to_f,
        timestamp: Time.current,
        tracker: tracker
      )
    rescue StandardError => e
      Rails.logger.warn("[PaperPnlRefresher] Failed refresh for #{tracker.id}: #{e.class} - #{e.message}")
    end

    def fetch_and_cache_fallback_ltp(tracker, segment:, security_id:)
      tradable = tracker.tradable
      if tradable
        ltp = tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        return cache_ltp_tick(segment: segment, security_id: security_id, ltp: ltp) if ltp.present?
      end

      return nil if ltp_api_rate_limited?(segment: segment, security_id: security_id)

      response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
      return nil unless response['status'] == 'success'

      option_data = response.dig('data', segment, security_id.to_s)
      return nil unless option_data && option_data['last_price']

      cache_ltp_tick(segment: segment, security_id: security_id, ltp: option_data['last_price'])
    rescue StandardError => e
      if rate_limit_error?(e)
        mark_ltp_api_rate_limited!(segment: segment, security_id: security_id)
      else
        Rails.logger.debug { "[PaperPnlRefresher] LTP fallback failed for #{segment}/#{security_id}: #{e.message}" }
      end
      nil
    end

    def cache_ltp_tick(segment:, security_id:, ltp:, timestamp: Time.current)
      ltp_bd = BigDecimal(ltp.to_s)
      return nil if ltp_bd <= 0

      Live::TickCache.put(
        segment: segment.to_s,
        security_id: security_id.to_s,
        ltp: ltp_bd.to_f,
        timestamp: timestamp,
        ts: timestamp.to_i
      )
      ltp_bd
    rescue StandardError => e
      Rails.logger.debug { "[PaperPnlRefresher] cache_ltp_tick failed for #{segment}/#{security_id}: #{e.message}" }
      nil
    end

    def rate_limit_error?(error)
      return false unless error

      message = error.message.to_s
      message.include?('429') || message.match?(/rate\s*limit/i) || error.class.name.include?('RateLimitError')
    end

    def ltp_api_rate_limited?(segment:, security_id:)
      Rails.cache.read(ltp_rate_limit_key(segment: segment, security_id: security_id)).present?
    rescue StandardError
      false
    end

    def mark_ltp_api_rate_limited!(segment:, security_id:)
      Rails.cache.write(ltp_rate_limit_key(segment: segment, security_id: security_id), true,
                        expires_in: LTP_RATE_LIMIT_COOLDOWN)
    rescue StandardError
      nil
    end

    def ltp_rate_limit_key(segment:, security_id:)
      "paper_pnl_refresher:ltp_rate_limit:#{segment}:#{security_id}"
    end

    def demand_driven_enabled?
      feature_flags[:enable_demand_driven_services] == true
    end

    def feature_flags
      AlgoConfig.fetch[:feature_flags] || {}
    rescue StandardError
      {}
    end

    def idle_interval_seconds
      interval_ms = AlgoConfig.fetch.dig(:risk, :loop_interval_idle) || (REFRESH_INTERVAL * 1000)
      interval_ms.to_f / 1000.0
    rescue StandardError
      REFRESH_INTERVAL
    end

    def active_interval_seconds
      interval_ms = AlgoConfig.fetch.dig(:risk, :loop_interval_active) || (REFRESH_INTERVAL * 1000)
      interval_ms.to_f / 1000.0
    rescue StandardError
      REFRESH_INTERVAL
    end

    def wait_for_interval(seconds)
      return sleep(seconds) unless demand_driven_enabled?

      @sleep_mutex.synchronize do
        @sleep_cv.wait(@sleep_mutex, seconds) if @running
      end
    end

    def wake_up!
      @sleep_mutex.synchronize do
        @sleep_cv.broadcast
      end
    end

    def subscribe_to_position_events
      return if @subscriptions.any?

      %w[positions.added positions.removed].each do |event|
        token = ActiveSupport::Notifications.subscribe(event) { wake_up! }
        @subscriptions << token
      end
    end

    def unsubscribe_from_position_events
      return if @subscriptions.empty?

      @subscriptions.each do |token|
        ActiveSupport::Notifications.unsubscribe(token)
      end
      @subscriptions.clear
    end
  end
end
