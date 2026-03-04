# frozen_string_literal: true

module Api
  class DashboardController < ApplicationController
    def show
      render json: {
        mode: AlgoConfig.mode,
        balance: safe_wallet_snapshot,
        today: PositionTracker.paper_trading_stats_with_pct,
        indices: {
          nifty: Live::TickCache.ltp('IDX_I', '13'),
          banknifty: Live::TickCache.ltp('IDX_I', '25'),
          sensex: Live::TickCache.ltp('IDX_I', '51')
        },
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        system: {
          ws_market_feed: Live::MarketFeedHub.instance.running?,
          ws_order_update: Live::OrderUpdateHub.instance.running?,
          scheduler: Thread.list.any? { |t| t.name == 'signal-scheduler' } ? 'running' : 'unknown'
        },
        timestamp: Time.current.iso8601
      }
    end

    private

    def safe_wallet_snapshot
      Orders.config.gateway.wallet_snapshot
    rescue StandardError
      { cash: Capital::Allocator.paper_trading_balance.to_f, equity: 0, mtm: 0, exposure: 0 }
    end
  end
end
