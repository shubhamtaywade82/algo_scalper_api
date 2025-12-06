# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
    def show
      render json: {
        mode: AlgoConfig.mode,
        watchlist: WatchlistItem.where(active: true).count,
        active_positions: PositionTracker.active.count,
        services: all_services_status,
        websocket: websocket_status,
        circuit_breaker: circuit_breaker_status
      }
    end

    private

    def all_services_status
      {
        market_feed_hub: service_status(:market_feed_hub),
        signal_scheduler: service_status(:signal_scheduler),
        risk_manager: service_status(:risk_manager),
        position_heartbeat: service_status(:position_heartbeat),
        order_router: service_status(:order_router),
        paper_pnl_refresher: service_status(:paper_pnl_refresher),
        exit_manager: service_status(:exit_manager),
        active_cache: service_status(:active_cache),
        reconciliation: service_status(:reconciliation),
        pnl_updater: pnl_updater_status,
        position_sync: position_sync_status,
        feed_health: feed_health_status,
        order_update_hub: order_update_hub_status
      }
    end

    def service_status(service_name)
      supervisor = Rails.application.config.x.trading_supervisor
      return { status: 'unknown', error: 'supervisor not available' } unless supervisor

      service = supervisor[service_name]
      return { status: 'not_registered' } unless service

      begin
        if service.respond_to?(:running?)
          running = service.running?
          status = running ? 'running' : 'stopped'
          result = { status: status }

          # Add service-specific health information
          result.merge!(service_health_details(service_name, service)) if running

          result
        elsif service.respond_to?(:start)
          # Service exists but doesn't have running? method
          { status: 'registered', note: 'no running? method' }
        else
          { status: 'unknown', note: 'service structure unclear' }
        end
      rescue StandardError => e
        { status: 'error', error: "#{e.class} - #{e.message}" }
      end
    end

    def service_health_details(service_name, service)
      case service_name
      when :market_feed_hub
        hub = Live::MarketFeedHub.instance
        {
          connected: hub.connected?,
          connection_state: hub.instance_variable_get(:@connection_state),
          last_tick_at: hub.instance_variable_get(:@last_tick_at),
          watchlist_size: hub.instance_variable_get(:@watchlist)&.count || 0
        }
      when :risk_manager
        risk_service = Live::RiskManagerService.instance
        risk_service.health_status
      when :signal_scheduler
        {
          thread_alive: Thread.list.any? { |t| t.name == 'signal-scheduler' && t.alive? }
        }
      when :reconciliation
        recon = Live::ReconciliationService.instance
        {
          thread_alive: recon.instance_variable_get(:@thread)&.alive? || false,
          stats: recon.stats
        }
      else
        {}
      end
    rescue StandardError => e
      { health_error: "#{e.class} - #{e.message}" }
    end

    def pnl_updater_status
      service = Live::PnlUpdaterService.instance
      {
        status: service.running? ? 'running' : 'stopped',
        thread_alive: service.instance_variable_get(:@thread)&.alive? || false
      }
    rescue StandardError => e
      { status: 'error', error: "#{e.class} - #{e.message}" }
    end

    def position_sync_status
      # PositionSyncService doesn't have a running? method - it's called on-demand
      # Check last sync time if available
      service = Live::PositionSyncService.instance
      last_sync = service.instance_variable_get(:@last_sync)
      {
        status: 'on_demand',
        last_sync: last_sync,
        sync_interval: service.instance_variable_get(:@sync_interval)
      }
    rescue StandardError => e
      { status: 'error', error: "#{e.class} - #{e.message}" }
    end

    def feed_health_status
      service = Live::FeedHealthService.instance
      {
        status: 'active',
        feed_statuses: service.status
      }
    rescue StandardError => e
      { status: 'error', error: "#{e.class} - #{e.message}" }
    end

    def order_update_hub_status
      service = Live::OrderUpdateHub.instance
      {
        status: service.running? ? 'running' : 'stopped',
        enabled: service.send(:enabled?)
      }
    rescue StandardError => e
      { status: 'error', error: "#{e.class} - #{e.message}" }
    end

    def websocket_status
      {
        market_feed: {
          running: Live::MarketFeedHub.instance.running?,
          connected: Live::MarketFeedHub.instance.connected?,
          health: Live::MarketFeedHub.instance.health_status
        },
        order_updates: {
          running: Live::OrderUpdateHub.instance.running?
        },
        tick_cache: {
          size: Live::TickCache.all.size,
          sample_ltps: {
            nifty: Live::TickCache.ltp('IDX_I', '13'),
            banknifty: Live::TickCache.ltp('IDX_I', '25'),
            sensex: Live::TickCache.ltp('IDX_I', '51')
          }
        }
      }
    rescue StandardError => e
      { error: "#{e.class} - #{e.message}" }
    end

    def circuit_breaker_status
      Risk::CircuitBreaker.instance.status
    rescue StandardError => e
      { error: "#{e.class} - #{e.message}" }
    end

    def scheduler_status
      Thread.list.any? { |thread| thread.name == 'signal-scheduler' } ? 'running' : 'unknown'
    end
  end
end
