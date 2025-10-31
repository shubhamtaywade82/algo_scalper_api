# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
    def show
      render json: {
        mode: AlgoConfig.mode,
        watchlist: WatchlistItem.where(active: true).count,
        active_positions: PositionTracker.where(status: PositionTracker::STATUSES[:active]).count,
        scheduler: scheduler_status,
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        websocket: {
          market_feed_running: Live::MarketFeedHub.instance.running?,
          # Note: Order updates use PositionSyncService polling (not WebSocket)
          order_update_running: Live::OrderUpdateHub.instance.running?,
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
