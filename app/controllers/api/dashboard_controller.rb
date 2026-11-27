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
        engine_diagnostics: build_engine_diagnostics,
        public_ipv4: ip_info[:public_ipv4],
        public_ipv6: ip_info[:public_ipv6],
        registered_ips: ip_info[:registered_ips],
        recent_signals: recent_signals_payload,
        strategies_summary: strategies_summary_payload,
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        system: Live::SystemStatusCache.instance.all_statuses,
        config: dashboard_config_payload,
        market_status: build_market_status,
        timestamp: Time.current.iso8601
      }
    end

    private

    def dashboard_config_payload
      {
        risk: AlgoConfig.fetch[:risk].slice(:sl_pct, :tp_pct, :hard_rupee_sl, :profit_floor, :trailing),
        signals: (AlgoConfig.fetch[:signals] || {}).slice(
          :enable_adx_filter, :adx, :enable_direction_gate,
          :enable_smc_confluence_digest, :enable_smc_confluence_gating, :smc_confluence_intervals
        ).compact,
        time_restrictions: AlgoConfig.fetch[:trading_time_restrictions],
        market_session: { current: Live::TimeRegimeService.instance.current_regime,
                          config: Live::TimeRegimeService.instance.regime_config }
      }
    end

    def formatted_indices
      load_indices = sorted_indices_with_strategy
      load_indices.to_h { |i| [i[:key].downcase.to_sym, i[:ltp]] }.merge(index_prev_closes(load_indices))
    end

    # Header/MarketWatch % change needs prev_close; the WS push only carries it intraday.
    def index_prev_closes(load_indices)
      %w[NIFTY BANKNIFTY SENSEX].to_h do |key|
        idx = load_indices.find { |i| i[:key] == key }
        prev = idx && Live::TickCache.fetch('IDX_I', idx[:sid].to_s)&.dig(:prev_close)
        [:"#{key.downcase}_prev_close", prev]
      end
    end

    def sorted_indices_with_strategy
      signals_cfg = AlgoConfig.fetch[:signals] || {}
      IndexConfigLoader.load_indices.map do |idx|
        idx.merge(
          symbol: idx[:symbol] || idx[:key],
          ltp: index_tick_ltp(idx[:segment], idx[:sid]),
          strategy: resolve_strategy_name(signals_cfg, idx[:key]),
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
      sorted_indices_with_strategy.map do |idx|
        key = idx[:key].to_s.upcase
        analysis = market_analysis_for_index(key)
        gate = gate_status_for_index(key)

        idx.merge(nearest_listed_option_expiry_fields(key)).merge(
          smc_confluence_ltf: confluence_ltf_from_analysis_store(key),
          bias: analysis[:bias],
          regime: analysis[:regime],
          is_trending: analysis[:is_trending],
          confidence: analysis[:confidence],
          supertrend: analysis[:supertrend],
          adx: analysis[:adx],
          market_analysis: analysis,
          gate_status: gate
        )
      end
    end

    def market_analysis_for_index(key)
      data = AnalysisStore.read(key, :regime)&.dig(:data) || {}
      supertrend = data[:supertrend] || data['supertrend'] || {}
      metrics = data[:metrics] || data['metrics'] || {}
      regime_str = (data[:regime] || data['regime'] || 'UNKNOWN').to_s.upcase
      st_dir = (supertrend[:direction] || supertrend['direction']).to_s.downcase

      {
        regime: regime_str,
        is_trending: regime_str.start_with?('TRENDING'),
        bias: resolve_bias(st_dir),
        confidence: (data[:confidence] || data['confidence'])&.to_f,
        supertrend: { direction: st_dir.presence, line: (supertrend[:line] || supertrend['line'])&.to_f },
        adx: (metrics[:adx_value] || metrics['adx_value'])&.to_f,
        volatility: (metrics[:volatility_regime] || metrics['volatility_regime'])&.to_s
      }
    rescue StandardError => e
      Rails.logger.debug { "[DashboardController] market_analysis #{key}: #{e.message}" }
      { regime: 'UNKNOWN', is_trending: false, bias: 'NEUTRAL', supertrend: {} }
    end

    def resolve_bias(st_dir)
      if %w[bullish buy].include?(st_dir)
        'BULLISH'
      elsif %w[bearish sell].include?(st_dir)
        'BEARISH'
      else
        'NEUTRAL'
      end
    end

    def gate_status_for_index(key)
      regime = (AnalysisStore.read(key, :regime)&.dig(:data, :regime) || 'UNKNOWN').to_s.upcase
      intent = defined?(TradeIntent) ? TradeIntent.where(underlying: key).order(id: :desc).first : nil

      if %w[CHOPPY RANGING].include?(regime)
        build_gate_hash('BLOCKED_CHOP', "#{regime} market: Longs blocked to avoid theta decay", intent)
      elsif intent && intent.created_at > 30.minutes.ago && intent.display_outcome == 'dropped'
        build_gate_hash('INTENT_DROPPED', "Last #{intent.direction} setup dropped: #{intent.outcome_code || 'Context rejected'}", intent)
      else
        build_gate_hash('SCANNING', 'Active scanning for valid trend continuation setup', intent)
      end
    rescue StandardError => e
      Rails.logger.debug { "[DashboardController] gate_status #{key}: #{e.message}" }
      { status: 'SCANNING', message: 'Scanning' }
    end

    def build_gate_hash(status, message, intent)
      {
        status: status,
        message: message,
        latest_intent_code: intent&.outcome_code,
        latest_intent_detail: intent&.outcome_detail
      }
    end

    def build_engine_diagnostics
      session_regime = Live::TimeRegimeService.instance.current_regime
      entry_allowed_res = TradingSession::Service.entry_allowed?
      entry_allowed = entry_allowed_res.is_a?(Hash) ? entry_allowed_res[:allowed] == true : entry_allowed_res == true
      market_open = TradingSession::Service.market_open?
      circuit_tripped = Risk::CircuitBreaker.instance.status[:tripped] == true
      status = determine_engine_status(market_open, circuit_tripped, entry_allowed)

      {
        status: status,
        market_open: market_open,
        entry_allowed: entry_allowed,
        session_regime: session_regime,
        circuit_tripped: circuit_tripped,
        overall_summary: summarize_engine_status(status, session_regime),
        recent_intents: recent_trade_intents_payload
      }
    end

    def determine_engine_status(market_open, circuit_tripped, entry_allowed)
      return 'MARKET_CLOSED' unless market_open
      return 'CIRCUIT_TRIPPED' if circuit_tripped
      return 'SESSION_BLOCKED' unless entry_allowed

      'ACTIVE_SCANNING'
    end

    def summarize_engine_status(status, session_regime)
      case status
      when 'MARKET_CLOSED'
        'Market is closed. Real-time scanning and executions paused until next session.'
      when 'CIRCUIT_TRIPPED'
        'Daily drawdown circuit breaker tripped. All new order entries are strictly halted.'
      when 'SESSION_BLOCKED'
        "Outside active entry window (#{session_regime.to_s.upcase} session). Holding existing positions; no new entries."
      else
        if session_regime.to_s.downcase == 'midday'
          'Midday session active (11:30 - 13:30). Conservative chop gates active to prevent theta decay.'
        else
          'Engine active and scanning for setups. Strict trend, structure & context alignment required.'
        end
      end
    end

    def recent_trade_intents_payload
      return [] unless defined?(TradeIntent)

      TradeIntent.order(id: :desc).limit(5).map do |ti|
        {
          id: ti.id, intent_id: ti.intent_id, underlying: ti.underlying, direction: ti.direction,
          strategy: ti.source_strategy, confidence: ti.confidence.to_f, outcome: ti.display_outcome,
          code: ti.outcome_code, detail: ti.outcome_detail, issued_at: ti.created_at&.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.debug { "[DashboardController] recent_trade_intents error: #{e.message}" }
      []
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

    def nearest_listed_option_expiry_fields(index_key)
      sym = index_key.to_s.upcase
      nearest = Instrument.options
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

    def recent_signals_payload
      ::Strategies::Signal.includes(:strategy_record).order(emitted_at: :desc).limit(10).map do |s|
        {
          timestamp: s.emitted_at&.strftime('%H:%M:%S'),
          strategy: s.strategy_record&.slug,
          signal: s.action&.upcase,
          symbol: s.instrument_key,
          confidence_level: s.confidence
        }
      end
    end

    def strategies_summary_payload
      ::Strategies::Record.order(:slug).pluck(:slug, :status).map do |slug, status|
        { name: slug, status: status == 'running' ? 'Running' : status.to_s.capitalize }
      end
    end

    def build_market_status
      today = Date.current
      holiday = MarketHoliday.find_by(exchange: :nse, observed_on: today)
      {
        is_trading_day: Market::Calendar.trading_day?(today),
        market_open: TradingSession::Service.market_open?,
        holiday_name: holiday&.name.presence,
        next_trading_day: Market::Calendar.next_trading_day.iso8601,
        session: TradingSession::Service.entry_allowed?
      }
    end
  end
end
