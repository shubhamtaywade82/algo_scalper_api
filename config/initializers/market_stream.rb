# frozen_string_literal: true

Rails.application.config.to_prepare do
  next unless Rails.application.config.x.respond_to?(:dhanhq)

  dhanhq_config = Rails.application.config.x.dhanhq
  next unless dhanhq_config&.enabled

  if dhanhq_config.ws_enabled && defined?(MarketFeedHub)
    MarketFeedHub.instance.start!
  elsif defined?(MarketFeedHub)
    MarketFeedHub.instance.stop!
  end

  if dhanhq_config.order_ws_enabled && defined?(Live::OrderUpdateHub)
    Live::OrderUpdateHub.instance.start!
  elsif defined?(Live::OrderUpdateHub)
    Live::OrderUpdateHub.instance.stop!
  end
end

at_exit do
  MarketFeedHub.instance.stop! if defined?(MarketFeedHub)
  Live::OrderUpdateHub.instance.stop! if defined?(Live::OrderUpdateHub)
  DhanHQ::WS.disconnect_all_local! if defined?(DhanHQ::WS)
end
