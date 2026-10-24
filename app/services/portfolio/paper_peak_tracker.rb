# frozen_string_literal: true

module Portfolio
  # Redis-backed daily high-water mark for paper total PnL (dashboard + Telegram stats).
  #
  # Portfolio::PnlTracker tracks live profit-lock net PnL; using it for paper dashboard
  # peak caused inflated / misleading "Daily Peak" when Redis state diverged from DB paper stats.
  #
  # This key is monotonic per calendar day (app TZ) and expires after 26 hours.
  class PaperPeakTracker
    REDIS_URL = ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')
    TTL = 26.hours.to_i

    class << self
      # Record a snapshot of paper session total PnL; ratchets stored peak upward only.
      #
      # @param total_pnl_rupees [Numeric]
      def observe!(total_pnl_rupees)
        total = total_pnl_rupees.to_f
        return unless total.finite?

        r = redis
        return unless r

        key = key_for(Time.zone.today)
        prev = r.get(key).to_f
        return if total <= prev

        r.set(key, total.round(2).to_s, ex: TTL)
      rescue StandardError => e
        Rails.logger.error("[Portfolio::PaperPeakTracker] observe! #{e.class} - #{e.message}")
      end

      # @param date [Date]
      # @return [Float]
      def current_for(date = Time.zone.today)
        redis&.get(key_for(date)).to_f
      rescue StandardError
        0.0
      end

      # Clear stored peak for +date+ (e.g. manual drawdown / session reset).
      #
      # @param date [Date]
      def reset_day!(date = Time.zone.today)
        r = redis
        return unless r

        r.del(key_for(date))
      rescue StandardError => e
        Rails.logger.error("[Portfolio::PaperPeakTracker] reset_day! #{e.class} - #{e.message}")
      end

      private

      def key_for(date)
        "portfolio:paper:daily_peak:#{date.strftime('%Y-%m-%d')}"
      end

      def redis
        @redis ||= Redis.new(url: REDIS_URL)
      rescue StandardError => e
        Rails.logger.error("[Portfolio::PaperPeakTracker] Redis init error: #{e.message}")
        nil
      end
    end
  end
end
