# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def show
      market_feed_status = Live::MarketFeedHub.instance.health_status
      order_update_status = Live::OrderUpdateHub.instance.respond_to?(:health_status) ? Live::OrderUpdateHub.instance.health_status : {}
      ip_info = Dhan::IpService.fetch_ip_info

      render json: {
        mode: AlgoConfig.mode,
        watchlist: WatchlistItem.where(active: true).count,
        active_positions: PositionTracker.active.count,
        scheduler: scheduler_status,
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        websocket: {
          market_feed_running: market_feed_status[:running],
          market_feed_connected: market_feed_status[:connected],
          market_feed_state: market_feed_status[:connection_state],
          market_feed_started_at: market_feed_status[:started_at],
          market_feed_last_tick_at: market_feed_status[:last_tick_at],
          order_update_running: order_update_status[:running],
          order_update_state: order_update_status[:connection_state],
          order_update_started_at: order_update_status[:started_at],
          order_update_last_update_at: order_update_status[:last_update_at],
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

    def scheduler_status
      Thread.list.any? { |thread| thread.name == 'signal-scheduler' } ? 'running' : 'unknown'
    end
  end
end
