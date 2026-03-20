# frozen_string_literal: true

module Portfolio
  class PnlTracker
    CACHE_KEY = 'portfolio:net_pnl'

    class << self
      # Refreshes and returns the current portfolio PnL state
      # @return [Hash] { total: Float, realized: Float, unrealized: Float, timestamp: Time }
      def refresh!
        realized = fetch_realized_pnl
        unrealized = fetch_unrealized_pnl
        total = realized + unrealized

        state = {
          total: total.to_f.round(2),
          realized: realized.to_f.round(2),
          unrealized: unrealized.to_f.round(2),
          timestamp: Time.current
        }

        # Cache for visibility and cross-service access
        Rails.cache.write(CACHE_KEY, state, expires_in: 1.minute)
        state
      end

      # Returns the last cached state or refreshes if empty
      def current
        Rails.cache.fetch(CACHE_KEY) { refresh! }
      end

      private

      def fetch_realized_pnl
        # Sum of PnL for all positions exited today (since market open at 9:15 AM IST)
        # Using 9:00 AM as a safe buffer for the start of the trading day
        today_start = TradingSession::Service.current_ist_time.change(hour: 9, min: 0)
        
        PositionTracker
          .where('exited_at >= ?', today_start)
          .where(status: 'exited')
          .sum(:last_pnl_rupees).to_f
      end

      def fetch_unrealized_pnl
        # Sum PnL from all currently active positions in memory
        Positions::ActiveCache.instance.all_positions.sum { |pos| pos.pnl.to_f }
      end
    end
  end
end
