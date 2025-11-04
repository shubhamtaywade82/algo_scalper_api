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
  # Skip automated trading services in console mode and test environment
  unless Rails.const_defined?(:Console) || Rails.env.test?
    # Start the live market feed hub
    MarketStreamLifecycle.safely_start { Live::MarketFeedHub.instance.start! }

    # DISABLED: Order Update WebSocket Handler
    # We use PositionSyncService polling approach instead for simplicity:
    # - PositionSyncService periodically polls DhanHQ REST API for active positions (every 30s)
    # - On sync, it finds untracked positions and creates PositionTracker records
    # - Active positions are automatically subscribed to market feed WebSocket
    # - This polling approach is simpler, more reliable, and sufficient for our use case
    # - Real-time order updates are not critical since position status changes are eventually consistent
    #
    # If you need real-time order updates (< 1s latency), uncomment the line below:
    # MarketStreamLifecycle.safely_start { Live::OrderUpdateHandler.instance.start! }

    # Start staggered OHLC intraday prefetch loop for watchlist
    MarketStreamLifecycle.safely_start { Live::OhlcPrefetcherService.instance.start! }

    # Start trading scheduler (signals → entries)
    MarketStreamLifecycle.safely_start { Signal::Scheduler.instance.start! }

    MarketStreamLifecycle.safely_start { Live::RiskManagerService.instance.start! }

    # Perform initial position sync to ensure all DhanHQ positions are tracked
    MarketStreamLifecycle.safely_start do
      # Rails.logger.info("[PositionSync] Performing initial position synchronization...")
      Live::PositionSyncService.instance.force_sync!
    end
  else
    # Rails.logger.info("[MarketStream] Skipping automated trading services in #{Rails.const_defined?(:Console) ? 'console' : 'test'} mode")
  end
end

at_exit do
  # Only stop services if they were started (not in console mode or test environment)
  unless Rails.const_defined?(:Console) || Rails.env.test?
    MarketStreamLifecycle.safely_stop { Live::MarketFeedHub.instance.stop! }
    # DISABLED: Order Update Handler stop (not started - see above)
    # MarketStreamLifecycle.safely_stop { Live::OrderUpdateHandler.instance.stop! }
    MarketStreamLifecycle.safely_stop { Live::OhlcPrefetcherService.instance.stop! }
    MarketStreamLifecycle.safely_stop { Signal::Scheduler.instance.stop! }
    MarketStreamLifecycle.safely_stop { DhanHQ::WS.disconnect_all_local! }
  end
end
