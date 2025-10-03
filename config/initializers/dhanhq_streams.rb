# frozen_string_literal: true

if defined?(DhanHQ) && Rails.application.config.x.respond_to?(:dhanhq)
  Rails.application.config.to_prepare do
    next unless Rails.application.config.x.dhanhq&.enabled

    if Rails.application.config.x.dhanhq.ws_enabled && defined?(Live::MarketFeedSupervisor)
      Live::MarketFeedSupervisor.instance.start!
    elsif defined?(Live::MarketFeedSupervisor)
      Live::MarketFeedSupervisor.instance.stop!
    end

    if Rails.application.config.x.dhanhq.order_ws_enabled && defined?(Live::OrderUpdateHub)
      Live::OrderUpdateHub.instance.start!
    elsif defined?(Live::OrderUpdateHub)
      Live::OrderUpdateHub.instance.stop!
    end
  end

  at_exit do
    if defined?(Live::MarketFeedSupervisor)
      Live::MarketFeedSupervisor.instance.stop!
    end

    if defined?(Live::OrderUpdateHub)
      Live::OrderUpdateHub.instance.stop!
    end
  end
else
  Rails.logger.info("DhanHQ WebSocket hooks skipped; configuration missing.")
end
