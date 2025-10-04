# frozen_string_literal: true

Rails.application.config.to_prepare do
  next unless Rails.application.config.x.respond_to?(:dhanhq)

  dhanhq_config = Rails.application.config.x.dhanhq
  next unless dhanhq_config&.enabled

  # Prefer the namespaced Live hub which uses DB-backed watchlist; fallback to legacy if needed
  if dhanhq_config.ws_enabled
    if defined?(Live::MarketFeedHub)
      Live::MarketFeedHub.instance.start!
    elsif defined?(MarketFeedHub)
      MarketFeedHub.instance.start!
    end
  else
    if defined?(Live::MarketFeedHub)
      Live::MarketFeedHub.instance.stop!
    elsif defined?(MarketFeedHub)
      MarketFeedHub.instance.stop!
    end
  end

  if dhanhq_config.order_ws_enabled && defined?(Live::OrderUpdateHub)
    Live::OrderUpdateHub.instance.start!
  elsif defined?(Live::OrderUpdateHub)
    Live::OrderUpdateHub.instance.stop!
  end
end

at_exit do
  Live::MarketFeedHub.instance.stop! if defined?(Live::MarketFeedHub)
  MarketFeedHub.instance.stop! if defined?(MarketFeedHub)
  Live::OrderUpdateHub.instance.stop! if defined?(Live::OrderUpdateHub)
  DhanHQ::WS.disconnect_all_local! if defined?(DhanHQ::WS)
end
