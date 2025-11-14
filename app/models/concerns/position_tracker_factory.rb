module PositionTrackerFactory
  extend ActiveSupport::Concern

  class_methods do
    def build_or_average!(instrument:, security_id:, segment:, quantity:, entry_price:, side:, symbol:, order_no:, meta: {})
      sid = security_id.to_s
      seg = segment.to_s

      # 1️⃣ Find active tracker
      active = PositionTracker.active.find_by(segment: seg, security_id: sid)

      if active
        Rails.logger.info("[TrackerFactory] Averaging -> #{seg}:#{sid} #{active.id}")

        old_qty = active.quantity.to_i
        new_qty = old_qty + quantity.to_i

        new_avg = (
          (active.entry_price.to_f * old_qty) +
          (entry_price.to_f * quantity.to_i)
        ) / new_qty

        active.update!(
          quantity: new_qty,
          entry_price: new_avg.round(2),
          avg_price: new_avg.round(2),
          meta: (active.meta || {}).merge(meta)
        )

        return active
      end

      # 2️⃣ No active tracker → create new one
      Rails.logger.info("[TrackerFactory] Creating NEW tracker for #{seg}:#{sid}")

      PositionTracker.create!(
        watchable: instrument.is_a?(Derivative) ? instrument : instrument,
        instrument: instrument.is_a?(Derivative) ? instrument.instrument : instrument,
        order_no: order_no,
        security_id: sid,
        symbol: symbol,
        segment: seg,
        side: side,
        quantity: quantity,
        entry_price: entry_price,
        avg_price: entry_price,
        status: PositionTracker::STATUSES[:active],
        meta: meta
      )
    end
  end
end
