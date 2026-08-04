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
        today: PositionTracker.trading_stats_with_pct,
        indices: formatted_indices,
        public_ipv4: ip_info[:public_ipv4],
        public_ipv6: ip_info[:public_ipv6],
        registered_ips: ip_info[:registered_ips],
        recent_signals: TradingSignal.order(created_at: :desc).limit(10).as_json(methods: [:confidence_level]),
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        system: Live::SystemStatusCache.instance.all_statuses,
        config: {
          risk: AlgoConfig.fetch[:risk].slice(:sl_pct, :tp_pct, :hard_rupee_sl, :profit_floor, :trailing),
          signals: (AlgoConfig.fetch[:signals] || {}).slice(
            :enable_adx_filter, :adx, :enable_direction_gate,
            :enable_smc_confluence_digest, :enable_smc_confluence_gating, :smc_confluence_intervals
          ).compact.merge(
            fast_entry_mode: Signal::FastEntryMode.status
          ),
          time_restrictions: AlgoConfig.fetch[:trading_time_restrictions],
          market_session: {
            current: Live::TimeRegimeService.instance.current_regime,
            config: Live::TimeRegimeService.instance.regime_config
          }
        },
        market_status: build_market_status,
        timestamp: Time.current.iso8601
      }
    end

    private

    def recent_signals_payload
      TradingSignal.order(created_at: :desc).limit(10).map do |signal|
        signal.as_json(methods: [:confidence_level]).merge(
          'metadata' => signal.effective_metadata
        )
      end
    end

    def formatted_indices
      load_indices = sorted_indices_with_strategy
      {
        nifty: load_indices.find { |i| i[:key] == 'NIFTY' }&.dig(:ltp),
        banknifty: load_indices.find { |i| i[:key] == 'BANKNIFTY' }&.dig(:ltp),
        sensex: load_indices.find { |i| i[:key] == 'SENSEX' }&.dig(:ltp),
        nifty_prev_close: Live::TickCache.fetch('IDX_I', '13')&.dig(:prev_close),
        banknifty_prev_close: Live::TickCache.fetch('IDX_I', '25')&.dig(:prev_close),
        sensex_prev_close: Live::TickCache.fetch('IDX_I', '51')&.dig(:prev_close)
      }
    end

    def sorted_indices_with_strategy
      signals_cfg = AlgoConfig.fetch[:signals] || {}
      IndexConfigLoader.load_indices.map do |idx|
        strategy_name = resolve_strategy_name(signals_cfg, idx[:key])

        idx.merge(
          ltp: index_tick_ltp(idx[:segment], idx[:sid]),
          strategy: strategy_name,
          timeframe: signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '1m'
        )
      end
    end

    # Index LTPs are written under Dhan's index segment (IDX_I) + security id. WatchlistItems
    # sometimes carry a different segment label; fall back so header LTPs match the live feed.
    def index_tick_ltp(segment, security_id)
      sid = security_id.to_s
      seg = segment.to_s
      val = Live::TickCache.ltp(seg, sid)
      return val if val.present?
      return nil if seg == 'IDX_I' || sid.blank?

      Live::TickCache.ltp('IDX_I', sid)
    end

    def subscribed_indices_payload
      indices = sorted_indices_with_strategy
      keys = indices.map { |idx| idx[:key].to_s.upcase }
      expiry_by_key = nearest_listed_option_expiry_batch(keys)

      indices.map do |idx|
        key = idx[:key].to_s.upcase
        idx.merge(expiry_by_key[key] || empty_nearest_option_expiry_fields).merge(
          smc_confluence_ltf: confluence_ltf_from_analysis_store(key)
        )
      end
    end

    def build_options_buying_payload
      {
        nifty: build_options_buying_state('NIFTY'),
        banknifty: build_options_buying_state('BANKNIFTY'),
        sensex: build_options_buying_state('SENSEX')
      }
    end

    def build_options_buying_state(index_key)
      direction = if OptionsBuying::StateStore.breakout_ready?(index_key, direction: :bullish)
                    'BULLISH'
                  elsif OptionsBuying::StateStore.breakout_ready?(index_key, direction: :bearish)
                    'BEARISH'
                  end
      {
        regime: OptionsBuying::RegimeClassifier.detect(index_key),
        breakout_ready: !direction.nil?,
        direction: direction,
        compression_armed: OptionsBuying::StateStore.compression_armed?(index_key),
        support: OptionsBuying::StateStore.support(index_key),
        resistance: OptionsBuying::StateStore.resistance(index_key),
        daily_atr: OptionsBuying::StateStore.daily_atr(index_key),
        radar_strikes: OptionsBuying::StateStore.radar_strikes(index_key)
      }
    rescue StandardError => e
      Rails.logger.warn("[DashboardController] failed to build options_buying state for #{index_key}: #{e.message}")
      { regime: 'UNKNOWN', breakout_ready: false, direction: nil }
    end

    def confluence_ltf_from_analysis_store(index_key)
      return nil unless AlgoConfig.fetch.dig(:signals, :enable_smc_confluence_digest) == true

      entry = AnalysisStore.read(index_key, :smc)
      data = entry&.dig(:data)
      return nil unless data.is_a?(Hash)

      summary = data[:smc_confluence_ltf_summary] || data["smc_confluence_ltf_summary"]
      summary.presence
    rescue StandardError => e
      Rails.logger.debug { "[DashboardController] confluence_ltf read #{index_key}: #{e.message}" }
      nil
    end

    def empty_nearest_option_expiry_fields
      { nearest_expiry: nil, days_to_expiry: nil, expiry_today: false }
    end

    # One grouped query for all underlyings (avoids N+1 on dashboard).
    def nearest_listed_option_expiry_batch(symbols)
      syms = Array(symbols).map { |s| s.to_s.upcase }.uniq
      return {} if syms.empty?

      mins = Derivative.options
                       .where(underlying_symbol: syms)
                       .where(expiry_date: Time.zone.today..)
                       .group(:underlying_symbol)
                       .minimum(:expiry_date)

      normalized = mins.transform_keys { |k| k.to_s.upcase }
      today = Time.zone.today

      syms.index_with do |sym|
        nearest = normalized[sym]
        next empty_nearest_option_expiry_fields unless nearest

        days = (nearest - today).to_i
        {
          nearest_expiry: nearest.iso8601,
          days_to_expiry: days,
          expiry_today: !days.positive?
        }
      end
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

    def build_market_status
      today = Date.current
      is_trading_day = Market::Calendar.trading_day?(today)
      market_open = TradingSession::Service.market_open?
      holiday = MarketHoliday.find_by(exchange: :nse, observed_on: today)

      {
        is_trading_day: is_trading_day,
        market_open: market_open,
        holiday_name: holiday&.name.presence,
        next_trading_day: Market::Calendar.next_trading_day.iso8601,
        session: TradingSession::Service.entry_allowed?
      }
    end

    def safe_wallet_snapshot
      Orders.config.gateway.wallet_snapshot
    rescue StandardError
      { cash: Capital::Allocator.paper_trading_balance.to_f, equity: 0, mtm: 0, exposure: 0 }
    end
  end
end
