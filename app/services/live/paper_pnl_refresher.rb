# frozen_string_literal: true

module Live
  class PaperPnlRefresher
    REFRESH_INTERVAL = 40 # seconds

    def initialize
      @thread = nil
      @running = false
      @lock = Mutex.new
    end

    def start
      @lock.synchronize do
        return if @running

        @running = true
        @thread = Thread.new { run_loop }
      end
    end

    def stop
      @lock.synchronize do
        @running = false
        @thread&.kill
        @thread&.join(1)
        @thread = nil
      end
    end

    private

    def run_loop
      Thread.current.name = "paper-pnl-refresher"

      loop do
        break unless @running
        begin
          refresh_all
        rescue StandardError => e
          Rails.logger.error("[PaperPnlRefresher] ERROR in run_loop: #{e.class} - #{e.message}")
        end
        sleep REFRESH_INTERVAL
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

      tracker.update!(
        last_pnl_rupees: pnl,
        last_pnl_pct: pct.round(2),
        high_water_mark_pnl: [tracker.high_water_mark_pnl.to_d, pnl].max
      )

      Live::RedisPnlCache.instance.store_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pct,
        ltp: ltp,
        hwm: tracker.high_water_mark_pnl,
        timestamp: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[PaperPnlRefresher] Failed refresh for #{tracker.id}: #{e.class} - #{e.message}")
    end
  end
end
