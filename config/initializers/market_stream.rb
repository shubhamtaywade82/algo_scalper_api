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

  # Resubscribe to all active PositionTracker positions after server restart
  def resubscribe_active_positions
    return unless defined?(PositionTracker)

    # Wait a moment for MarketFeedHub to be ready
    sleep(0.5)

    # Can't eagerly load polymorphic :watchable, so just load instrument
    active_positions = PositionTracker.active.includes(:instrument).to_a
    return if active_positions.empty?

    subscribed_count = 0
    failed_count = 0

    active_positions.each do |tracker|
      begin
        tracker.subscribe
        subscribed_count += 1
      rescue StandardError => e
        Rails.logger.error("[MarketStream] Failed to resubscribe position #{tracker.order_no}: #{e.message}")
        failed_count += 1
      end
    end

    Rails.logger.info("[MarketStream] Resubscribed to #{subscribed_count} active positions#{failed_count.positive? ? " (#{failed_count} failed)" : ''}")
  rescue StandardError => e
    Rails.logger.error("[MarketStream] Failed to resubscribe active positions: #{e.class} - #{e.message}")
  end
end

# Rails.application.config.to_prepare do
#   # Skip automated trading services in console mode and test environment
#   is_rake = defined?(Rake)
#   backtest_env = ENV['BACKTEST_MODE'] == '1'
#   backtest_task = is_rake && Rake.application.respond_to?(:top_level_tasks) && Rake.application.top_level_tasks.any? { |t| t.start_with?('backtest:') }
#   skip_services = Rails.const_defined?(:Console) || Rails.env.test? || backtest_env || backtest_task

#   unless skip_services
#     # 1️⃣ Start Market Feed Hub
#     MarketStreamLifecycle.safely_start { Live::MarketFeedHub.instance.start! }

#     # DISABLED: Order Update WebSocket Handler
#     # We use PositionSyncService polling approach instead for simplicity:
#     # - PositionSyncService periodically polls DhanHQ REST API for active positions (every 30s)
#     # - On sync, it finds untracked positions and creates PositionTracker records
#     # - Active positions are automatically subscribed to market feed WebSocket
#     # - This polling approach is simpler, more reliable, and sufficient for our use case
#     # - Real-time order updates are not critical since position status changes are eventually consistent
#     #
#     # If you need real-time order updates (< 1s latency), uncomment the line below:
#     # MarketStreamLifecycle.safely_start { Live::OrderUpdateHandler.instance.start! }

#     # 2️⃣ Start Signal Scheduler # Start trading scheduler (signals → entries)
#     MarketStreamLifecycle.safely_start { Signal::Scheduler.instance.start! }

#     # 3️⃣ Start Risk Manager Service
#     MarketStreamLifecycle.safely_start { Live::RiskManagerService.instance.start! }

#     # 4️⃣ Start new PnL Updater Service # Start real-time PnL updater (computes pnl:tracker data every second from TickCache)
#     # Start PnL updater service (batch writer) — start after market feed hub is up
#     MarketStreamLifecycle.safely_start do
#       # tiny delay to let MarketFeedHub/TickCache populate initial ticks
#       Thread.new do
#         sleep 0.5
#         Live::PnlUpdaterService.instance.start!
#       end
#     end

#     # 5️⃣ Resubscribe & Sync Positions (syncs positions from DhanHQ and creates PositionTracker records) # Resubscribe to all active positions after MarketFeedHub starts
#     MarketStreamLifecycle.safely_start { resubscribe_active_positions }

#     # Perform initial position sync to ensure all DhanHQ positions are tracked
#     MarketStreamLifecycle.safely_start { Live::PositionSyncService.instance.force_sync! }
#   else
#     # Rails.logger.info("[MarketStream] Skipping automated trading services in #{Rails.const_defined?(:Console) ? 'console' : 'test'} mode")
#   end
# end

# # Graceful shutdown handler
# def shutdown_services
#   return if Rails.const_defined?(:Console) || Rails.env.test?

#   Rails.logger.info('[MarketStream] Shutting down services...') if defined?(Rails.logger)

#   # Stop all services in reverse order of startup
#   MarketStreamLifecycle.safely_stop { Live::PnlUpdaterService.instance.stop! }
#   MarketStreamLifecycle.safely_stop { Live::RiskManagerService.instance.stop! }
#   MarketStreamLifecycle.safely_stop { Signal::Scheduler.instance.stop! }
#   MarketStreamLifecycle.safely_stop { Live::MarketFeedHub.instance.stop! }
#   # DISABLED: Order Update Handler stop (not started - see above)
#   # MarketStreamLifecycle.safely_stop { Live::OrderUpdateHandler.instance.stop! }

#   # Disconnect all WebSocket connections
#   MarketStreamLifecycle.safely_stop { DhanHQ::WS.disconnect_all_local! }

#   Rails.logger.info('[MarketStream] Services shut down successfully') if defined?(Rails.logger)
# rescue StandardError => e
#   Rails.logger.error("[MarketStream] Error during shutdown: #{e.class} - #{e.message}") if defined?(Rails.logger)
# end

# # Register signal handlers for graceful shutdown on Ctrl+C (SIGINT) or kill (SIGTERM)
# %w[INT TERM].each do |signal|
#   Signal.trap(signal) do
#     Rails.logger.info("[MarketStream] Received #{signal} signal, shutting down...") if defined?(Rails.logger)
#     shutdown_services
#     exit(0)
#   end
# end

# # Also register at_exit hook as fallback
# at_exit do
#   shutdown_services
# end

# frozen_string_literal: true

# Skip in console and tests
return if Rails.const_defined?(:Console) || Rails.env.test?

Rails.application.config.after_initialize do
  # ensure services start only once per process
  unless defined?($market_stream_started) && $market_stream_started
    $market_stream_started = true

    # --- SERVICE STARTUP ---
    MarketStreamLifecycle.safely_start { Live::MarketFeedHub.instance.start! }
    MarketStreamLifecycle.safely_start { Signal::Scheduler.instance.start! }
    MarketStreamLifecycle.safely_start { Live::RiskManagerService.instance.start! }

    Thread.new do
      sleep(0.5)
      MarketStreamLifecycle.safely_start { Live::PnlUpdaterService.instance.start! }
    end

    MarketStreamLifecycle.safely_start { MarketStreamLifecycle.resubscribe_active_positions }
    MarketStreamLifecycle.safely_start { Live::PositionSyncService.instance.force_sync! }

    # --- REGISTER ONE-TIME SIGNAL HANDLERS ---
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        Rails.logger.info("[MarketStream] Received #{signal}, shutting down...") if defined?(Rails.logger)
        shutdown_services
        exit(0)
      end
    end

    # --- AT EXIT ---
    at_exit do
      shutdown_services
    end
  end
end

def shutdown_services
  return if Rails.const_defined?(:Console) || Rails.env.test?

  Rails.logger.info('[MarketStream] Shutting down services...') if defined?(Rails.logger)

  MarketStreamLifecycle.safely_stop { Live::PnlUpdaterService.instance.stop! }
  MarketStreamLifecycle.safely_stop { Live::RiskManagerService.instance.stop! }
  MarketStreamLifecycle.safely_stop { Signal::Scheduler.instance.stop! }
  MarketStreamLifecycle.safely_stop { Live::MarketFeedHub.instance.stop! }
  MarketStreamLifecycle.safely_stop { DhanHQ::WS.disconnect_all_local! }

  Rails.logger.info('[MarketStream] Services shut down successfully') if defined?(Rails.logger)
rescue => e
  Rails.logger.error("[MarketStream] Shutdown error: #{e.class} - #{e.message}") if defined?(Rails.logger)
end
