# frozen_string_literal: true

# Register EventBus subscribers for broadcast-then-forget events.
# Add new subscribers here to keep core flow decoupled from logging, metrics, notifications.
Rails.application.config.after_initialize do
  bus = Core::EventBus.instance
  next if bus.subscriber_count(:exit_triggered).positive?

  bus.subscribe(:exit_triggered) do |event|
    next unless event.is_a?(Hash)

    Rails.logger.debug(
      "[EventBus] exit_triggered: tracker_id=#{event[:tracker_id]} order_no=#{event[:order_no]} " \
      "reason=#{event[:reason]} exit_price=#{event[:exit_price]}"
    )

    tracker_id = event[:tracker_id]
    index_key = event[:index_key]
    reason = event[:reason]
    if tracker_id.present? && index_key.present?
      tracker = PositionTracker.find_by(id: tracker_id)
      if tracker&.exited? && tracker.last_pnl_rupees.present?
        Live::EdgeFailureDetector.instance.record_trade_result(
          index_key: index_key,
          pnl_rupees: tracker.last_pnl_rupees.to_f,
          exit_reason: reason.to_s,
          exit_time: Time.current
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error("[EventBus] exit_triggered subscriber error: #{e.class} - #{e.message}")
  end
end
