module TradingSystem
  class OrderRouter
    def initialize
      @running = false
    end

    def start = @running = true
    def stop = @running = false

    def exit_market(tracker)
      segment     = tracker.segment
      security_id = tracker.security_id.to_i

      # 1) PAPER → instant exit
      return { success: true, paper: true } if tracker.paper?

      # 2) LIVE → use your actual flat_position API
      begin
        # FIX: must call Orders::Service NOT Orders::Manager
        order = Orders::Service.flat_position(
          segment: segment,
          security_id: security_id
        )

        if order.present?
          Rails.logger.info("[OrderRouter] Flattened position #{tracker.order_no} SID=#{security_id}")
          { success: true }
        else
          Rails.logger.error("[OrderRouter] FAILED to flatten #{tracker.order_no} SID=#{security_id}")
          { success: false }
        end
      rescue StandardError => e
        Rails.logger.error("[OrderRouter] crash while exiting #{tracker.order_no}: #{e.class} - #{e.message}")
        { success: false }
      end
    end
  end
end
