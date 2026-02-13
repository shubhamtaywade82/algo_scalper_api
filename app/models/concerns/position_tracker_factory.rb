# frozen_string_literal: true

module PositionTrackerFactory
  extend ActiveSupport::Concern

  class_methods do
    def build_or_average!(instrument:, security_id:, segment:, quantity:, entry_price:, side:, symbol:, order_no:,
                          meta: {}, watchable: nil, status: 'active', trade_state: nil)
      sid = security_id.to_s
      seg = segment.to_s

      # 1️⃣ Find active tracker
      active = PositionTracker.active.find_by(segment: seg, security_id: sid)

      if active
        # HARD RULE: No averaging down / no averaging up.
        # If a tracker is already active for this derivative, return it unchanged.
        Rails.logger.warn("[TrackerFactory] Averaging blocked (no-avg rule) -> #{seg}:#{sid} #{active.id}")
        return active
      end

      # 2️⃣ No active tracker → create new one
      Rails.logger.info("[TrackerFactory] Creating NEW tracker for #{seg}:#{sid}")

      PositionTracker.create!(
        watchable: watchable || (instrument.is_a?(Derivative) ? instrument : instrument),
        instrument: if watchable
                      watchable.is_a?(Derivative) ? watchable.instrument : watchable
                    else
                      (instrument.is_a?(Derivative) ? instrument.instrument : instrument)
                    end,
        order_no: order_no,
        security_id: sid,
        symbol: symbol,
        segment: seg,
        side: side,
        quantity: quantity,
        entry_price: entry_price,
        avg_price: entry_price,
        status: status,
        meta: meta,
        trade_state: trade_state
      )
    end
  end
end
