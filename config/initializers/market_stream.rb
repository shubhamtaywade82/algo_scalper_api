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
    # Start the live market feed hub
    MarketStreamLifecycle.safely_start { Live::MarketFeedHub.instance.start! }

    # Optional order updates (handler internally starts the hub)
    MarketStreamLifecycle.safely_start { Live::OrderUpdateHandler.instance.start! }

    # Start staggered OHLC intraday prefetch loop for watchlist
    MarketStreamLifecycle.safely_start { Live::OhlcPrefetcherService.instance.start! }

    # Start trading scheduler (signals → entries)
    MarketStreamLifecycle.safely_start { Signal::Scheduler.instance.start! }

    MarketStreamLifecycle.safely_start { Live::RiskManagerService.instance.start! }

    # Start ATM options service for live trading
    MarketStreamLifecycle.safely_start { Live::AtmOptionsService.instance.start! }

    # Perform initial position sync to ensure all DhanHQ positions are tracked
    MarketStreamLifecycle.safely_start do
      Rails.logger.info("[PositionSync] Performing initial position synchronization...")
      Live::PositionSyncService.instance.force_sync!
    end
  else
    Rails.logger.info("[MarketStream] Skipping automated trading services in console mode")
  end
end

at_exit do
  # Only stop services if they were started (not in console mode)
  unless Rails.const_defined?(:Console)
    MarketStreamLifecycle.safely_stop { Live::MarketFeedHub.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::OrderUpdateHandler.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::OhlcPrefetcherService.instance.stop! }
    MarketStreamLifecycle.safely_stop { Signal::Scheduler.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::AtmOptionsService.instance.stop! }
    MarketStreamLifecycle.safely_stop { DhanHQ::WS.disconnect_all_local! }
  end
end
