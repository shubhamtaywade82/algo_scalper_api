# frozen_string_literal: true

module Orders
  # Background worker and service for reconciling internal positions/orders
  # with broker REST endpoints (orders, tradebook, positions).
  class Reconciler
    class << self
      def call
        new.reconcile_all!
      end
    end

    def reconcile_all!
      unreconciled_trackers = PositionTracker.where(status: PositionTracker.statuses.values_at('pending', 'active'))
      reconciled_count = 0

      unreconciled_trackers.each do |tracker|
        reconcile_tracker!(tracker)
        reconciled_count += 1
      rescue StandardError => e
        Rails.logger.error("[Orders::Reconciler] Failed for tracker #{tracker.id}: #{e.message}")
      end

      reconciled_count
    end

    def reconcile_tracker!(tracker)
      return unless tracker

      remote_pos = fetch_remote_position(tracker)
      if remote_pos.blank? || remote_pos[:qty].to_i.zero?
        mark_as_exited_or_cancelled!(tracker)
      else
        update_pnl_and_status!(tracker, remote_pos)
      end
    end

    private

    def fetch_remote_position(tracker)
      gateway = Orders.config.gateway
      gateway.position(segment: tracker.segment, security_id: tracker.security_id)
    rescue StandardError => e
      Rails.logger.warn("[Orders::Reconciler] Position fetch failed for #{tracker.security_id}: #{e.message}")
      nil
    end

    def mark_as_exited_or_cancelled!(tracker)
      target = tracker.entry_price.present? ? :exited : :cancelled
      Orders::Fsm.transition!(tracker, target, metadata: { reconciled_by: 'Orders::Reconciler' })
      tracker.update!(status: target, exited_at: Time.current) if tracker.respond_to?(:update!)

      EventStore::Publisher.publish!(
        stream: 'orders',
        event_type: 'trading.order.reconciled',
        correlation_id: tracker.order_no.to_s,
        payload: { tracker_id: tracker.id, new_status: target },
        decision_id: EventStore::DecisionTrace.current_id
      )
    end

    def update_pnl_and_status!(tracker, remote_pos)
      upnl = remote_pos[:upnl] || 0
      current_price = remote_pos[:last_ltp] || tracker.avg_price

      tracker.update!(
        avg_price: current_price,
        last_pnl_rupees: upnl,
        updated_at: Time.current
      )

      Orders::Fsm.transition!(tracker, :reconciled, metadata: { remote_qty: remote_pos[:qty] })

      EventStore::Publisher.publish!(
        stream: 'orders',
        event_type: 'trading.order.reconciled',
        correlation_id: tracker.order_no.to_s,
        payload: { tracker_id: tracker.id, upnl: upnl, current_price: current_price },
        decision_id: EventStore::DecisionTrace.current_id
      )
    end
  end
end
