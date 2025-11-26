# frozen_string_literal: true

module Live
  class PaperPnlRefresher
    REFRESH_INTERVAL = (AlgoConfig.fetch.dig(:paper_trading, :realtime_interval_seconds) || 1).to_i # seconds

    def initialize
      @thread = nil
      @running = false
      @lock = Mutex.new
      @sleep_mutex = Mutex.new
      @sleep_cv = ConditionVariable.new
      @subscriptions = []
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
      trackers = PositionTracker.paper.active

      trackers.find_each do |t|
        refresh_tracker(t)
      end
    end

    def refresh_tracker(tracker)
      seg = tracker.segment || tracker.watchable&.exchange_segment
      sid = tracker.security_id

      return if seg.blank? || sid.blank?

      ltp = Live::TickCache.ltp(seg, sid)
      return unless ltp.present?

      entry = BigDecimal(tracker.entry_price.to_s)
      qty   = tracker.quantity.to_i
      pnl   = (ltp.to_d - entry) * qty.to_d
      pct   = entry.positive? ? ((ltp.to_d - entry) / entry * 100) : 0

      hwm_pnl = [tracker.high_water_mark_pnl.to_d, pnl].max
      hwm_pnl_pct = entry.positive? ? ((hwm_pnl / (entry * qty)) * 100) : 0

      tracker.update!(
        last_pnl_rupees: pnl,
        last_pnl_pct: pct.round(2),
        high_water_mark_pnl: hwm_pnl
      )

      Live::RedisPnlCache.instance.store_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pct,
        ltp: ltp,
        hwm: hwm_pnl,
        hwm_pnl_pct: hwm_pnl_pct.round(2),
        timestamp: Time.current,
        tracker: tracker
      )
    rescue StandardError => e
      Rails.logger.warn("[PaperPnlRefresher] Failed refresh for #{tracker.id}: #{e.class} - #{e.message}")
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
