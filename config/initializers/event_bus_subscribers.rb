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
  end
end
