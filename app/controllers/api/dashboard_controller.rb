# frozen_string_literal: true

module Api
  class DashboardController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def show
      ip_info = Dhan::IpService.fetch_ip_info
      render json: {
        mode: AlgoConfig.mode,
        balance: safe_wallet_snapshot,
        today: PositionTracker.paper_trading_stats_with_pct,
        indices: formatted_indices,
        subscribed_indices: subscribed_indices_payload,
        public_ipv4: ip_info[:public_ipv4],
        public_ipv6: ip_info[:public_ipv6],
        registered_ips: ip_info[:registered_ips],
        recent_signals: TradingSignal.order(created_at: :desc).limit(10).as_json(methods: [:confidence_level]),
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        system: Live::SystemStatusCache.instance.all_statuses.merge(
          ws_order_update: Live::OrderUpdateHub.instance.running?,
          pnl_updater_running: Live::PnlUpdaterService.instance.running?
        ),
        config: {
          risk: AlgoConfig.fetch[:risk].slice(:sl_pct, :tp_pct, :hard_rupee_sl, :profit_floor, :trailing),
          signals: AlgoConfig.fetch[:signals].slice(:enable_adx_filter, :adx, :enable_direction_gate),
          time_restrictions: AlgoConfig.fetch[:trading_time_restrictions],
          market_session: {
            current: Live::TimeRegimeService.instance.current_regime,
            config: Live::TimeRegimeService.instance.regime_config
          }
        },
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
        strategy_name = resolve_strategy_name(signals_cfg, idx[:key])

        idx.merge(
          ltp: Live::TickCache.ltp(idx[:segment], idx[:sid]),
          strategy: strategy_name,
          timeframe: signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '1m'
        )
      end
    end

    def subscribed_indices_payload
      sorted_indices_with_strategy.map do |idx|
        key = idx[:key].to_s.upcase
        idx.merge(nearest_listed_option_expiry_fields(key))
      end
    end

    def nearest_listed_option_expiry_fields(index_key)
      sym = index_key.to_s.upcase
      nearest = Derivative.options
                          .where(underlying_symbol: sym)
                          .where(expiry_date: Time.zone.today..)
                          .minimum(:expiry_date)
      return { nearest_expiry: nil, days_to_expiry: nil, expiry_today: false } unless nearest

      days = (nearest - Time.zone.today).to_i
      {
        nearest_expiry: nearest.iso8601,
        days_to_expiry: days,
        expiry_today: !days.positive?
      }
    end

    def resolve_strategy_name(signals_cfg, index_key)
      entry_cfg = signals_cfg[:entry_strategy]
      entry_primary = (entry_cfg.is_a?(Hash) ? entry_cfg[:primary] : entry_cfg).to_s.strip.downcase

      if entry_primary == 'supertrend'
        'supertrend_trend'
      elsif signals_cfg[:use_strategy_recommendations]
        rec = StrategyRecommender.best_for_index(symbol: index_key)
        rec ? "#{rec[:strategy_name]} (#{rec[:interval]}m)" : 'supertrend_adx'
      else
        'supertrend_adx'
      end
    end

    def safe_wallet_snapshot
      Orders.config.gateway.wallet_snapshot
    rescue StandardError
      { cash: Capital::Allocator.paper_trading_balance.to_f, equity: 0, mtm: 0, exposure: 0 }
    end
  end
end
