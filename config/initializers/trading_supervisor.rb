# frozen_string_literal: true

# disable completely?
if ENV["DISABLE_TRADING_SUPERVISOR"].to_s == "true"
  Rails.logger.info("[Supervisor] Disabled in this container")
  return
end

# --------------------------------------------------------------------
# REGISTER-ONLY INITIALIZER (no auto-start)
# --------------------------------------------------------------------
#
# Trading services are started by a separate process:
#   ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
#
# The web server should not auto-start long-running threads.
if Rails.env.test? ||
  defined?(Rails::Console) ||
  (defined?(Rails::Generators) && Rails::Generators.const_defined?(:Base))
 return
end

# bin/dev uses Puma, not Rails::Server
# is_web_process =
#  $PROGRAM_NAME.include?("puma") ||
#  $PROGRAM_NAME.include?("rails") ||
#  ENV["WEB_CONCURRENCY"].present?

# Running inside worker, not web
is_worker = ENV["WORKER_MODE"].to_s == "true"
return unless is_worker

# return unless is_web_process

# --------------------------------------------------------------------
# SUPERVISOR - NO SINGLETONS
# --------------------------------------------------------------------
module TradingSystem
 class Supervisor
   def initialize
     @services = {}     # { name => service_instance }
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
         Rails.logger.info("[Supervisor] started #{name}")
       rescue => e
         Rails.logger.error("[Supervisor] failed starting #{name}: #{e.class} - #{e.message}")
       end
     end

     @running = true
   end

   def stop_all
     return unless @running

     @services.reverse_each do |name, service|
       begin
         service.stop
         Rails.logger.info("[Supervisor] stopped #{name}")
       rescue => e
         Rails.logger.error("[Supervisor] error stopping #{name}: #{e.class} - #{e.message}")
       end
     end

     @running = false
   end
 end
end

# --------------------------------------------------------------------
# SERVICE ADAPTERS
# --------------------------------------------------------------------

# Wrap Live::MarketFeedHub singleton
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

  delegate :subscribe_many, to: :@hub
end

# Wrap your existing PnlUpdaterService singleton
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

# ActiveCache service adapter
class ActiveCacheService
  def initialize
    @cache = Positions::ActiveCache.instance
  end

  def start
    @cache.start!
  end

  def stop
    @cache.stop!
  end
end

# SMC Live Service adapter
class LiveSmcServiceAdapter
  def initialize
    @service = Smc::LiveSmcService.instance
  end

  def start
    @service.start
  end

  def stop
    @service.stop
  end
end

# --------------------------------------------------------------------
# INITIALIZER (runs on each reload in dev)
# --------------------------------------------------------------------
Rails.application.config.to_prepare do
  supervisor = TradingSystem::Supervisor.new

  # # Register services through adapters
  # supervisor.register(:market_feed, MarketFeedHubService.new)
  # supervisor.register(:signal_scheduler, Signal::Scheduler.new)
  # supervisor.register(:risk_manager,     Live::RiskManagerService.new)
  # supervisor.register(:position_heartbeat, TradingSystem::PositionHeartbeat.new)
  # supervisor.register(:order_router, TradingSystem::OrderRouter.new)
  # supervisor.register(:position_heartbeat, TradingSystem::PositionHeartbeat.new)
  # supervisor.register(:paper_pnl_refresher, Live::PaperPnlRefresher.new)
  # supervisor.register(
  #   :exit_manager,
  #   Live::ExitEngine.new(order_router: TradingSystem::OrderRouter.new)
  # )

  feed = MarketFeedHubService.new
  router = TradingSystem::OrderRouter.new
  exit_engine = Live::ExitEngine.new(order_router: router)

  supervisor.register(:market_feed, feed)
  supervisor.register(:signal_scheduler, Signal::Scheduler.new)
  supervisor.register(:risk_manager, Live::RiskManagerService.new(exit_engine: exit_engine))
  supervisor.register(:position_heartbeat, TradingSystem::PositionHeartbeat.new)
  supervisor.register(:order_router, router)
  supervisor.register(:paper_pnl_refresher, Live::PaperPnlRefresher.new)
  supervisor.register(:exit_manager, exit_engine)
  supervisor.register(:active_cache, ActiveCacheService.new)
  supervisor.register(:reconciliation, Live::ReconciliationService.instance)
  supervisor.register(:live_smc, LiveSmcServiceAdapter.new)

 # Future:
 # supervisor.register(:pnl_updater, PnlUpdaterServiceAdapter.new)
 # supervisor.register(:risk_manager, TradingSystem::RiskManager.new)
 # supervisor.register(:order_router, TradingSystem::OrderRouter.new)

 unless defined?($trading_supervisor_started) && $trading_supervisor_started
   $trading_supervisor_started = true

   # Check if market is closed - if so, only start WebSocket connection
   market_closed = TradingSession::Service.market_closed?

   if market_closed
     Rails.logger.info('[TradingSupervisor] Market is closed - only starting WebSocket connection')
     # Only start MarketFeedHub (WebSocket connection)
     supervisor[:market_feed]&.start
     Rails.logger.info('[Supervisor] started market_feed (WebSocket only)')
   else
     # Market is open - start all services
     supervisor.start_all
   end

   # ----------------------------------------------------
   # SUBSCRIBE ACTIVE POSITIONS VIA PositionIndex
   # ----------------------------------------------------
   # Only subscribe active positions if market is open
   unless market_closed
     active_pairs = Live::PositionIndex.instance.all_keys.map do |k|
        seg, sid = k.split(':', 2)
       { segment: seg, security_id: sid }
     end

      supervisor[:market_feed].subscribe_many(active_pairs) if active_pairs.any?
   end

   # ----------------------------------------------------
   # SIGNAL HANDLERS (CTRL+C)
   # ----------------------------------------------------
   %w[INT TERM].each do |sig|
     Signal.trap(sig) do
       Rails.logger.info("[TradingSupervisor] Received #{sig}, shutting down...")
       supervisor.stop_all
        exit(0) # rubocop:disable Rails/Exit
     end
   end

   # ----------------------------------------------------
   # at_exit fallback
   # ----------------------------------------------------
   at_exit do
     supervisor.stop_all
   end
 end

 Rails.application.config.x.trading_supervisor = supervisor
end
