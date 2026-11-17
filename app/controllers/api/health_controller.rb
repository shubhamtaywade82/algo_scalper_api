# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def show
      # The hubs only run in the trading daemon; the web process must read the shared heartbeats.
      statuses = Live::SystemStatusCache.instance.all_statuses
      Dhan::IpService.fetch_ip_info

      render json: {
        mode: AlgoConfig.mode,
        watchlist: WatchlistItem.where(active: true).count,
        active_positions: PositionTracker.active.count,
        scheduler: scheduler_status,
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        websocket: {
          market_feed_connected: statuses[:ws_market_feed],
          market_feed_last_tick_at: last_index_tick_at,
          order_update_connected: statuses[:ws_order_update],
          pnl_updater_running: statuses[:pnl_updater_running],
          tick_cache_size: Live::TickCache.all.size,
          sample_ltps: {
            nifty: Live::TickCache.ltp('IDX_I', '13'),
            banknifty: Live::TickCache.ltp('IDX_I', '25'),
            sensex: Live::TickCache.ltp('IDX_I', '51')
          }
        }
      }
    end

    private

    def last_index_tick_at
      Live::TickCache.fetch('IDX_I', '13')&.dig(:cached_at)
    end

    def scheduler_status
      Thread.list.any? { |thread| thread.name == 'signal-scheduler' } ? 'running' : 'unknown'
    end
  end
end
