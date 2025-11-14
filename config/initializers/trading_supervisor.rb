# frozen_string_literal: true

# Run ONLY inside Rails server, not in console/test/vite/webpack
return unless defined?(Rails::Server)
return if Rails.env.test?
return if Rails.const_defined?(:Console)

# A very small, controlled Supervisor (no Singletons here)
module TradingSystem
  class Supervisor
    def initialize
      @services = {}
      @running  = false
    end

    def register(name, instance)
      @services[name] = instance
    end

    def [](name)
      @services[name]
    end

    def start_all
      return if @running

      @services.each do |name, service|
        begin
          service.start
          Rails.logger.info("[Supervisor] Started #{name}")
        rescue => e
          Rails.logger.error("[Supervisor] Failed starting #{name}: #{e.class} - #{e.message}")
        end
      end

      @running = true
    end

    def stop_all
      return unless @running

      @services.reverse_each do |name, service|
        begin
          service.stop
          Rails.logger.info("[Supervisor] Stopped #{name}")
        rescue => e
          Rails.logger.error("[Supervisor] Error stopping #{name}: #{e.class} - #{e.message}")
        end
      end

      @running = false
    end
  end
end

# --------------------------
# Service Adapters
# --------------------------

# Wrap your existing Singleton MarketFeedHub in a Supervisor-friendly wrapper
class MarketFeedHubService
  def initialize
    @hub = Live::MarketFeedHub.instance
  end

  def start
    @hub.start!
  end

  def stop
    @hub.stop!
  end
end

# Wrap PnlUpdaterService (your existing class)
class PnlUpdaterServiceAdapter
  def initialize
    @svc = Live::PnlUpdaterService.instance
  end

  def start
    @svc.start!
  end

  def stop
    @svc.stop!
  end
end

Rails.application.config.after_initialize do
  supervisor = TradingSystem::Supervisor.new

  # 1) MARKET FEED HUB
  supervisor.register(:market_feed, MarketFeedHubService.new)

  # 2) PNL UPDATER SERVICE
  supervisor.register(:pnl_updater, PnlUpdaterServiceAdapter.new)

  # Load PositionIndex early (optional but good)
  begin
    Live::PositionIndex.instance.bulk_load_active!
  rescue => e
    Rails.logger.warn("[Supervisor] PositionIndex load failed: #{e.class} - #{e.message}")
  end

  # Start all services
  supervisor.start_all

  # Shutdown hooks
  %w[INT TERM].each do |sig|
    Signal.trap(sig) do
      Rails.logger.info("[Supervisor] Received #{sig}, shutting down...")
      supervisor.stop_all
      exit(0)
    end
  end

  at_exit do
    supervisor.stop_all
  end

  Rails.application.config.x.trading_supervisor = supervisor
end
