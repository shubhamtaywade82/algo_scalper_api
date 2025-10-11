# frozen_string_literal: true

Rails.application.config.to_prepare do
  # Try to start the live feed hub; it internally checks ENV/config and no-ops if disabled
  if defined?(Live::MarketFeedHub)
    Live::MarketFeedHub.instance.start!
  elsif defined?(MarketFeedHub)
    MarketFeedHub.instance.start!
  end

  # Optional order updates (only starts if defined and configured inside the hub)
  Live::OrderUpdateHub.instance.start! if defined?(Live::OrderUpdateHub)
  Live::OrderUpdateHandler.instance.start! if defined?(Live::OrderUpdateHandler)

  # Start staggered OHLC intraday prefetch loop for watchlist
  Live::OhlcPrefetcherService.instance.start! if defined?(Live::OhlcPrefetcherService)

  # Start trading scheduler (signals → entries) - only in server mode
  Signal::Scheduler.new.start! if defined?(Signal::Scheduler) && !Rails.const_defined?(:Console)

  Live::RiskManagerService.instance.start! if defined?(Live::RiskManagerService)
end

at_exit do
  Live::MarketFeedHub.instance.stop! if defined?(Live::MarketFeedHub)
  MarketFeedHub.instance.stop! if defined?(MarketFeedHub)
  Live::OrderUpdateHub.instance.stop! if defined?(Live::OrderUpdateHub)
  Live::OrderUpdateHandler.instance.stop! if defined?(Live::OrderUpdateHandler)
  Live::OhlcPrefetcherService.instance.stop! if defined?(Live::OhlcPrefetcherService)
  DhanHQ::WS.disconnect_all_local! if defined?(DhanHQ::WS)
end
