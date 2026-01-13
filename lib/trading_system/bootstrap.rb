# frozen_string_literal: true

module TradingSystem
  # Centralized wiring for trading services.
  #
  # Used by:
  # - the register-only Rails initializer (web process)
  # - the trading daemon (separate long-running process)
  module Bootstrap
    module_function

    def build_supervisor
      supervisor = TradingSystem::Supervisor.new

      feed = Live::MarketFeedHubService.new
      router = TradingSystem::OrderRouter.new
      exit_engine = Live::ExitEngine.new(order_router: router)

      supervisor.register(:market_feed, feed)
      supervisor.register(:signal_scheduler, Signal::Scheduler.new)
      supervisor.register(:risk_manager, Live::RiskManagerService.new(exit_engine: exit_engine))
      supervisor.register(:position_heartbeat, TradingSystem::PositionHeartbeat.new)
      supervisor.register(:order_router, router)
      supervisor.register(:paper_pnl_refresher, Live::PaperPnlRefresher.new)
      supervisor.register(:exit_manager, exit_engine)
      # ActiveCacheService is defined at top level in app/services/positions/active_cache_service.rb
      # Explicitly load it since Zeitwerk won't autoload top-level constants from nested paths
      unless defined?(::ActiveCacheService)
        file_path = if defined?(Rails)
                      Rails.root.join('app/services/positions/active_cache_service.rb')
                    else
                      File.join(
                        __dir__, '../../app/services/positions/active_cache_service.rb'
                      )
                    end
        load file_path.to_s if File.exist?(file_path.to_s)
      end
      supervisor.register(:active_cache, ::ActiveCacheService.new)
      supervisor.register(:reconciliation, Live::ReconciliationService.instance)
      supervisor.register(:stats_notifier, Live::StatsNotifierService.instance)
      supervisor.register(:smc_scanner, Smc::Scanner.new)

      supervisor
    end
  end
end
