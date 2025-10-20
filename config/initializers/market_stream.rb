# frozen_string_literal: true

module MarketStreamLifecycle
  module_function

  def safely_start
    yield
  rescue NameError
    nil
  end

  def safely_stop
    yield
  rescue NameError
    nil
  end
end

Rails.application.config.to_prepare do
  # Skip automated trading services in console mode
  unless Rails.const_defined?(:Console)
    # Try to start the live feed hub; it internally checks ENV/config and no-ops if disabled
    started = MarketStreamLifecycle.safely_start { Live::MarketFeedHub.instance.start! }
    MarketStreamLifecycle.safely_start { MarketFeedHub.instance.start! } unless started

    # Optional order updates (only starts if defined and configured inside the hub)
    MarketStreamLifecycle.safely_start { Live::OrderUpdateHub.instance.start! }
    MarketStreamLifecycle.safely_start { Live::OrderUpdateHandler.instance.start! }

    # Start staggered OHLC intraday prefetch loop for watchlist
    MarketStreamLifecycle.safely_start { Live::OhlcPrefetcherService.instance.start! }

    # Start trading scheduler (signals → entries)
    MarketStreamLifecycle.safely_start { Signal::Scheduler.instance.start! }

    MarketStreamLifecycle.safely_start { Live::RiskManagerService.instance.start! }

    # Start ATM options service for live trading
    MarketStreamLifecycle.safely_start { Live::AtmOptionsService.instance.start! }
  else
    Rails.logger.info("[MarketStream] Skipping automated trading services in console mode")
  end
end

at_exit do
  # Only stop services if they were started (not in console mode)
  unless Rails.const_defined?(:Console)
    MarketStreamLifecycle.safely_stop { Live::MarketFeedHub.instance.stop! }
    MarketStreamLifecycle.safely_stop { MarketFeedHub.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::OrderUpdateHub.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::OrderUpdateHandler.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::OhlcPrefetcherService.instance.stop! }
    MarketStreamLifecycle.safely_stop { Signal::Scheduler.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::AtmOptionsService.instance.stop! }
    MarketStreamLifecycle.safely_stop { DhanHQ::WS.disconnect_all_local! }
  end
end
