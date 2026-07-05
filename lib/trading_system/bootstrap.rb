# frozen_string_literal: true

module TradingSystem
  # Centralized wiring for trading services.
  #
  # Used by:
  # - the register-only Rails initializer (web process)
  # - the trading daemon (separate long-running process)
  module Bootstrap
    module_function

    # Performs startup reconciliation so broker and DB position state are aligned
    # before risk and signal services start.
    # @param strict [Boolean] raise on reconciliation errors when true
    # @return [Object] sync result from PositionSyncService
    def boot_reconciliation!(strict: true)
      Rails.logger.info('[Bootstrap] Running startup broker reconciliation...')
      Live::PositionSyncService.instance.force_sync!
    rescue StandardError => e
      Rails.logger.fatal("[Bootstrap] Reconciliation failed: #{e.class} - #{e.message}")
      raise if strict

      false
    end

    # Evaluates session gates that normally run on the 9:01 recurring job.
    # Called when the trading daemon starts during market hours so late boots
    # do not leave VIX entry_allowed? fail-open until the next 15m refresh.
    def boot_market_gates!
      vix = Market::VixGate.evaluate!
      return log_vix_gate_skipped unless vix

      Rails.logger.info(
        "[Bootstrap] India VIX gate at boot: VIX=#{vix.round(2)} " \
        "entry_allowed=#{Market::VixGate.entry_allowed?} " \
        "force_exit=#{Market::VixGate.force_exit_active?}"
      )
      vix
    rescue StandardError => e
      Rails.logger.error("[Bootstrap] boot_market_gates! #{e.class} - #{e.message}")
      nil
    end

    def log_vix_gate_skipped
      Rails.logger.warn('[Bootstrap] India VIX gate not evaluated at boot (disabled or LTP unavailable)')
      nil
    end
    private :log_vix_gate_skipped

    def build_supervisor
      supervisor = TradingSystem::Supervisor.new

      feed = Live::MarketFeedHubService.new
      router = TradingSystem::OrderRouter.new
      exit_engine = Live::ExitEngine.new(order_router: router)

      supervisor.register(:market_feed, feed)
      supervisor.register(:tick_smc_ai, Smc::TickAi::AnalysisService.new)
      supervisor.register(:options_buying_breakout, OptionsBuying::BreakoutWatcher.new)
      supervisor.register(:options_buying_stream_consumer, OptionsBuying::StreamConsumer.new)
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
      supervisor.register(:active_cache, Positions::ActiveCacheService.new)
      supervisor.register(:reconciliation, Live::ReconciliationService.instance)
      supervisor.register(:stats_notifier, Live::StatsNotifierService.instance)
      supervisor.register(:smc_scanner, Smc::Scanner.new)
      supervisor.register(:chain_watch_nifty, Options::ChainWatchService.new(index_key: 'NIFTY'))
      supervisor.register(:chain_watch_banknifty, Options::ChainWatchService.new(index_key: 'BANKNIFTY'))
      supervisor.register(:chain_watch_sensex, Options::ChainWatchService.new(index_key: 'SENSEX'))

      supervisor
    end
  end
end
