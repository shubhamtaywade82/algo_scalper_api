# frozen_string_literal: true

module Live
  # Detects live (non-paper) entries DhanHQ never confirmed as filled or rejected,
  # despite the tracker being optimistically marked `active` at placement time (see
  # Entries::EntryGuard#create_tracker!). Only checks a narrow window after entry —
  # checking every active position on every run forever would burn broker API calls
  # for positions whose fill was already confirmed hours ago.
  class CancelStuckOrdersJob < ApplicationJob
    queue_as :background

    CHECK_WINDOW_START = 60.seconds
    CHECK_WINDOW_END = 10.minutes

    def perform
      candidates.find_each { |tracker| check_tracker(tracker) }
    end

    private

    def candidates
      PositionTracker
        .active
        .where(paper: false)
        .where(created_at: CHECK_WINDOW_END.ago..CHECK_WINDOW_START.ago)
    end

    def check_tracker(tracker)
      status = fetch_status(tracker.order_no)

      if Live::OrderUpdateHandler::CANCELLED_STATUSES.include?(status)
        reconcile_incorrectly_active!(tracker, status)
      elsif Live::OrderUpdateHandler::FILL_STATUSES.exclude?(status)
        cancel_stuck_order!(tracker, status)
      end
    rescue StandardError => e
      Rails.logger.error("[CancelStuckOrdersJob] Failed checking #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def fetch_status(order_no)
      DhanHQ::Models::Order.find(order_no)&.order_status.to_s.upcase
    end

    # Broker actually rejected/cancelled this order, but our tracker still shows active —
    # the WebSocket update was missed. Correct our state rather than leave a phantom position.
    def reconcile_incorrectly_active!(tracker, status)
      Rails.logger.error("[CancelStuckOrdersJob] #{tracker.order_no} is #{status} at broker but tracker shows active; correcting")
      tracker.with_lock { tracker.mark_cancelled! }
      notify("#{tracker.order_no} was #{status} at DhanHQ but our tracker showed active — corrected to cancelled.")
    end

    # Order genuinely never confirmed (still pending/transit) well past when a market
    # order should have filled. Cancel it, then re-check once before touching our own
    # tracker — a fill can land in the gap between our check and the cancel request.
    def cancel_stuck_order!(tracker, status)
      Rails.logger.error("[CancelStuckOrdersJob] #{tracker.order_no} unconfirmed (status=#{status}) after #{CHECK_WINDOW_START.to_i}s; attempting cancel")

      begin
        DhanHQ::Models::Order.find(tracker.order_no).cancel
      rescue StandardError => e
        Rails.logger.error("[CancelStuckOrdersJob] Cancel request failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end

      final_status = fetch_status(tracker.order_no)
      if Live::OrderUpdateHandler::FILL_STATUSES.include?(final_status)
        Rails.logger.warn("[CancelStuckOrdersJob] #{tracker.order_no} filled just as we tried to cancel it — leaving tracker active")
        return
      end

      tracker.with_lock { tracker.mark_cancelled! }
      notify("#{tracker.order_no} never confirmed by DhanHQ (status=#{status}); cancelled and marked tracker cancelled.")
    end

    def notify(message)
      Notifications::TelegramNotifier.instance.notify_error(message, context: 'Live::CancelStuckOrdersJob')
    rescue StandardError => e
      Rails.logger.error("[CancelStuckOrdersJob] Telegram notify failed: #{e.message}")
    end
  end
end
