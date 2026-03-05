# frozen_string_literal: true

module Api
  class DashboardController < ApplicationController
    def show
      render json: {
        mode: AlgoConfig.mode,
        balance: safe_wallet_snapshot,
        today: PositionTracker.paper_trading_stats_with_pct,
        indices: formatted_indices,
        recent_signals: TradingSignal.order(created_at: :desc).limit(10).as_json(methods: [:confidence_level]),
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        system: Live::SystemStatusCache.instance.all_statuses.merge(
          ws_order_update: Live::OrderUpdateHub.instance.running?
        ),
        timestamp: Time.current.iso8601
      }
    end

    private

    def formatted_indices
      load_indices = sorted_indices_with_strategy
      {
        nifty: load_indices.find { |i| i[:key] == 'NIFTY' }&.dig(:ltp),
        banknifty: load_indices.find { |i| i[:key] == 'BANKNIFTY' }&.dig(:ltp),
        sensex: load_indices.find { |i| i[:key] == 'SENSEX' }&.dig(:ltp)
      }
    end

    def sorted_indices_with_strategy
      signals_cfg = AlgoConfig.fetch[:signals] || {}
      IndexConfigLoader.load_indices.map do |idx|
        # Determine strategy from config (mimicking Signal::Engine logic)
        entry_primary = (signals_cfg.dig(:entry_strategy, :primary) || signals_cfg[:entry_strategy].to_s).to_s.strip.downcase

        strategy_name = if entry_primary == 'supertrend'
                          'supertrend_trend'
                        elsif signals_cfg[:use_strategy_recommendations]
                          rec = StrategyRecommender.best_for_index(symbol: idx[:key])
                          rec ? "#{rec[:strategy_name]} (#{rec[:interval]}m)" : 'supertrend_adx'
                        else
                          'supertrend_adx'
                        end

        idx.merge(
          ltp: Live::TickCache.ltp(idx[:segment], idx[:sid]),
          strategy: strategy_name,
          timeframe: signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '1m'
        )
      end
    end
    def safe_wallet_snapshot
      Orders.config.gateway.wallet_snapshot
    rescue StandardError
      { cash: Capital::Allocator.paper_trading_balance.to_f, equity: 0, mtm: 0, exposure: 0 }
    end
  end
end
