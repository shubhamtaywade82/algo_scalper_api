# frozen_string_literal: true

require 'digest'

module Reports
  module MarketBrief
    # Stage 1 of the Market Brief: a deterministic, read-only snapshot of
    # market facts, strategy decisions, risk state and system health.
    #
    # Every value is read from an existing authoritative cross-process source
    # (Redis tick cache, AnalysisStore, Rails.cache gates, Redis heartbeats,
    # PostgreSQL). Nothing here places, modifies or cancels orders, fetches
    # candles from DhanHQ, or recomputes indicators.
    #
    # Value conventions (schema v1):
    #   * every section carries a +status+: ok | fresh | live | stale | last_session |
    #     invalid | unavailable | error — never inferred from the value itself
    #   * nil means "not known"; 0 is only emitted when the source reported 0
    #   * timestamps are ISO8601; +age_seconds+ is measured against +generated_at+
    class SnapshotBuilder
      QUOTE_LIVE_MAX_AGE = 15 # seconds; index ticks arrive sub-second while the feed is up
      RECONCILIATION_MAX_AGE = 5.minutes
      REJECTION_REASON_LIMIT = 6
      UNSUPPORTED_CONTEXT = %w[market_breadth fii_dii_flows sector_performance global_indices news].freeze
      HEALTHY_COMPONENT = %w[ok not_required].freeze
      LIVE_STATUSES = %w[live fresh].freeze
      SMC_DECISIONS = { 'call' => 'CALL', 'put' => 'PUT', 'no_trade' => 'NO_TRADE' }.freeze

      def self.call(now: Time.current)
        new(now: now).call
      end

      def initialize(now: Time.current)
        @now = now
        @ist_now = now.in_time_zone(TradingSession::Service::IST_TIMEZONE)
        @warnings = []
      end

      def call
        session = section(:session) { build_session }
        indices = index_configs.map { |cfg| section("index:#{cfg[:key]}") { build_index(cfg, session) } }
        market_context = section(:market_context) { build_market_context }
        risk = section(:risk) { build_risk }
        health = section(:health) { build_health(indices) }
        setup = section(:setup) do
          SetupSelector.new(
            mode: mode, now: @now, index_keys: index_configs.pluck(:key),
            session: session, risk: risk, health: health, market_context: market_context, indices: indices
          ).call
        end

        snapshot = {
          schema_version: MarketBriefReport::SCHEMA_VERSION,
          generated_at: @now.iso8601,
          trading_date: @ist_now.to_date.iso8601,
          timezone: TradingSession::Service::IST_TIMEZONE,
          mode: mode.to_s,
          session: session,
          indices: indices,
          market_context: market_context,
          setup: setup,
          risk: risk,
          health: health,
          warnings: @warnings.uniq
        }
        snapshot = snapshot.deep_stringify_keys
        snapshot['freshness'] = overall_freshness(snapshot)
        snapshot
      end

      # Stable identity of the facts so AI output can be tied to (and reused for)
      # exactly the facts it interpreted. Generation time and the ages derived from
      # it are excluded; the underlying observation timestamps and statuses are not.
      # Keys are sorted so the digest survives a jsonb round-trip (jsonb reorders keys).
      def self.digest(snapshot)
        canonical = canonicalize(snapshot.deep_stringify_keys.except('generated_at', 'freshness'))
        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end

      def self.canonicalize(value)
        case value
        when Hash then value.except('age_seconds').sort.to_h { |k, v| [k, canonicalize(v)] }
        when Array then value.map { |v| canonicalize(v) }
        else value
        end
      end

      private

      attr_reader :now

      def mode
        @mode ||= AlgoConfig.mode
      end

      def paper?
        mode.to_s == 'paper'
      end

      def index_configs
        @index_configs ||= Array(IndexConfigLoader.load_indices).filter_map do |idx|
          key = idx[:key].to_s.upcase
          next if key.blank?

          { key: key, sid: idx[:sid].to_s, segment: idx[:segment].to_s }
        end
      end

      # Isolates failures: one broken source degrades its own section only.
      def section(name)
        yield
      rescue StandardError => e
        Rails.logger.warn("[MarketBrief::SnapshotBuilder] #{name} failed: #{e.class} - #{e.message}")
        @warnings << "#{name}_unavailable"
        { status: 'error', error: e.class.name }
      end

      # ------------------------------------------------------------------
      # Session
      # ------------------------------------------------------------------

      def build_session
        today = @ist_now.to_date
        trading_day = Market::Calendar.trading_day?(today)
        holiday = MarketHoliday.find_by(exchange: :nse, observed_on: today)
        entry_window = TradingSession::Service.entry_allowed?

        status = if !trading_day
                   holiday ? 'holiday' : 'closed'
                 elsif TradingSession::Service.market_open?
                   'open'
                 elsif TradingSession::Service.after_market_close_time?
                   'post_close'
                 else
                   'pre_market'
                 end

        @warnings << 'market_not_open' unless status == 'open'

        {
          status: status,
          is_trading_day: trading_day,
          holiday_name: holiday&.name.presence,
          next_trading_day: Market::Calendar.next_trading_day&.iso8601,
          entry_window_open: trading_day && entry_window[:allowed] == true,
          entry_window_reason: entry_window[:reason]
        }
      end

      def market_open?(session)
        session.is_a?(Hash) && session[:status] == 'open'
      end

      # ------------------------------------------------------------------
      # Indices
      # ------------------------------------------------------------------

      def build_index(cfg, session)
        key = cfg[:key]
        regime = build_regime(key)
        smc = build_smc(key)

        {
          index_key: key,
          quote: build_quote(cfg, session),
          regime: regime,
          supertrend: { status: 'unavailable', reason: 'no_cross_process_supertrend_snapshot' },
          smc: smc,
          bias: build_bias(regime, smc),
          expiry: build_expiry(key)
        }
      end

      def build_quote(cfg, session)
        tick = Live::TickQuery.for_security(segment: cfg[:segment], security_id: cfg[:sid])
        tick ||= Live::TickQuery.for_security(segment: 'IDX_I', security_id: cfg[:sid]) unless cfg[:segment] == 'IDX_I'
        return { status: 'unavailable' }.tap { @warnings << "#{cfg[:key]}_quote_unavailable" } unless tick

        ltp = tick.ltp.to_f
        prev_close = tick.prev_close.to_f.positive? ? tick.prev_close.to_f : nil
        observed_at = parse_time(tick.timestamp)
        freshness = tick.freshness(QUOTE_LIVE_MAX_AGE)

        status = if freshness == :invalid then 'invalid'
                 elsif !market_open?(session) then 'last_session'
                 elsif freshness == :fresh then 'live'
                 else 'stale'
                 end
        @warnings << "#{cfg[:key]}_quote_#{status}" if %w[invalid stale].include?(status)

        {
          status: status,
          ltp: ltp.positive? ? ltp.round(2) : nil,
          prev_close: prev_close&.round(2),
          change_pct: (ltp.positive? && prev_close ? ((ltp - prev_close) / prev_close * 100).round(2) : nil),
          observed_at: observed_at&.iso8601,
          age_seconds: age(observed_at)
        }
      end

      def build_regime(index_key)
        entry = AnalysisStore.read(index_key, :regime)
        return { status: 'unavailable' }.tap { @warnings << "#{index_key}_regime_unavailable" } unless entry

        data = stringify(entry[:data]) || {}
        metrics = stringify(data['metrics']) || {}
        validity = stringify(entry[:validity]) || {}
        label = data['regime'].to_s.upcase.presence
        no_data = %w[NO_DATA INSUFFICIENT_DATA].include?(label)
        status = if no_data then 'unavailable'
                 elsif validity['fresh'] then 'fresh'
                 else 'stale'
                 end
        @warnings << "#{index_key}_regime_#{status}" unless status == 'fresh'

        {
          status: status,
          label: label,
          adx: numeric(metrics['adx_value']),
          atr_percent: numeric(metrics['atr_percent']),
          volatility_regime: metrics['volatility_regime']&.to_s,
          bb_breakout: metrics.key?('bb_breakout') ? metrics['bb_breakout'] == true : nil,
          timeframe_minutes: 5,
          computed_at: validity['computed_at'],
          age_seconds: validity['age_seconds']
        }
      end

      def build_smc(index_key)
        entry = AnalysisStore.read(index_key, :smc)
        return { status: 'unavailable' }.tap { @warnings << "#{index_key}_smc_unavailable" } unless entry

        data = stringify(entry[:data]) || {}
        validity = stringify(entry[:validity]) || {}
        frames = stringify(data['timeframes']) || {}
        status = validity['fresh'] ? 'fresh' : 'stale'
        @warnings << "#{index_key}_smc_stale" if status == 'stale'

        {
          status: status,
          decision: smc_decision(data['decision']),
          timeframes: %w[htf mtf ltf].index_with { |tf| smc_frame(frames[tf]) },
          computed_at: validity['computed_at'],
          age_seconds: validity['age_seconds']
        }
      end

      def smc_frame(frame)
        frame = stringify(frame)
        return { status: 'unavailable' } unless frame

        ctx = stringify(frame['context']) || {}
        swing = stringify(ctx['swing_structure']) || stringify(ctx['structure']) || {}
        liquidity = stringify(ctx['liquidity']) || {}
        pd = stringify(ctx['premium_discount']) || {}

        {
          status: 'ok',
          interval: frame['interval']&.to_s,
          trend: direction_label(ctx['trend'] || swing['trend']),
          phase: ctx['phase']&.to_s,
          last_bos: scalar_slice(swing['last_bos']),
          liquidity_sweep: liquidity.key?('sweep') ? liquidity['sweep'] == true : nil,
          sweep_direction: liquidity['sweep_direction']&.to_s,
          active_fvg_count: count_of(stringify(ctx['fvg'])&.dig('active')),
          active_order_block_count: count_of(stringify(ctx['order_blocks'])&.dig('active')),
          zone: zone_label(pd)
        }
      end

      def build_bias(regime, smc)
        technical = case regime[:label]
                    when 'TRENDING_UP' then 'BULLISH'
                    when 'TRENDING_DOWN' then 'BEARISH'
                    when 'RANGING', 'CHOPPY' then 'NEUTRAL'
                    else 'UNAVAILABLE'
                    end
        technical = 'UNAVAILABLE' if regime[:status] == 'unavailable'

        smc_bias = case smc[:decision]
                   when 'CALL' then 'BULLISH'
                   when 'PUT' then 'BEARISH'
                   when 'NO_TRADE' then 'NEUTRAL'
                   else 'UNAVAILABLE'
                   end
        smc_bias = 'UNAVAILABLE' if smc[:status] == 'unavailable'

        trends = Array(smc[:timeframes]&.values).pluck(:trend)
        mtf = if trends.empty? || trends.any? { |t| t.nil? || t == 'UNAVAILABLE' } then 'UNAVAILABLE'
              elsif trends.all?('BULLISH') then 'ALIGNED_BULLISH'
              elsif trends.all?('BEARISH') then 'ALIGNED_BEARISH'
              else 'MIXED'
              end

        agreement = if [technical, smc_bias].include?('UNAVAILABLE') then 'UNAVAILABLE'
                    elsif technical == smc_bias then 'AGREE'
                    elsif [technical, smc_bias].include?('NEUTRAL') then 'PARTIAL'
                    else 'CONFLICT'
                    end

        { technical: technical, smc: smc_bias, mtf_alignment: mtf, agreement: agreement }
      end

      def build_expiry(index_key)
        nearest = Instrument.options
                            .where(underlying_symbol: index_key)
                            .where(expiry_date: @ist_now.to_date..)
                            .minimum(:expiry_date)
        return { status: 'unavailable' } unless nearest

        { status: 'ok', nearest_expiry: nearest.iso8601, days_to_expiry: (nearest - @ist_now.to_date).to_i }
      end

      # ------------------------------------------------------------------
      # Market context
      # ------------------------------------------------------------------

      def build_market_context
        vix_value = Market::VixGate.current_ltp
        evaluated = Market::VixGate.evaluated?
        observed_at = parse_time(Rails.cache.read(Market::VixGate::CACHE_TS_KEY))

        {
          vix: {
            status: vix_value&.positive? ? 'ok' : 'unavailable',
            value: vix_value&.positive? ? vix_value.round(2) : nil,
            evaluated: evaluated,
            entry_allowed: Market::VixGate.entry_allowed?,
            force_exit_active: Market::VixGate.force_exit_active?,
            observed_at: observed_at&.iso8601,
            age_seconds: age(observed_at)
          },
          # No verified source is wired for these; they are reported as unavailable
          # rather than approximated from index indicators.
          unavailable: UNSUPPORTED_CONTEXT
        }
      end

      # ------------------------------------------------------------------
      # Risk & portfolio
      # ------------------------------------------------------------------

      def build_risk
        active = PositionTracker.active.where(paper: paper?).includes(:instrument, :watchable).to_a
        positions = active.map { |t| position_row(t) }
        exposure = active.sum { |t| t.entry_price.to_f * t.quantity.to_i }
        capital = Capital::Allocator.available_cash.to_f
        pnl = session_pnl(active)
        breaker = Risk::CircuitBreaker.instance.status
        loss = daily_loss(capital)
        reconciliation = latest_reconciliation

        {
          status: 'ok',
          pnl: pnl,
          active_positions_count: active.size,
          active_positions: positions,
          capital_available: capital.positive? ? capital.round(2) : nil,
          exposure_rupees: exposure.round(2),
          exposure_pct_of_capital: capital.positive? ? (exposure / capital * 100).round(2) : nil,
          daily_loss: loss,
          circuit_breaker: { tripped: breaker[:tripped] == true, reason: breaker[:reason], at: breaker[:at]&.to_s },
          reconciliation_discrepancies: reconciliation[:discrepancies]
        }
      end

      def position_row(tracker)
        row = Positions::Serializer.open(tracker)
        row.slice(:id, :symbol, :side, :quantity, :index_key, :entry_price, :ltp, :pnl, :pnl_pct, :sl_price, :tp_price)
      rescue StandardError => e
        Rails.logger.warn("[MarketBrief::SnapshotBuilder] position #{tracker.id} serialize failed: #{e.class}")
        { id: tracker.id, symbol: tracker.symbol, status: 'error' }
      end

      # Same definition as the dashboard (PositionTracker.paper_trading_stats_with_pct):
      # realized = today's exited trackers' last_pnl_rupees, unrealized = active current_pnl_rupees.
      def session_pnl(active)
        if paper?
          stats = PositionTracker.paper_trading_stats_with_pct
          return {
            realized_rupees: stats[:realized_pnl_rupees],
            unrealized_rupees: stats[:unrealized_pnl_rupees],
            total_rupees: stats[:total_pnl_rupees],
            closed_trades: stats[:total_trades],
            winners: stats[:winners],
            losers: stats[:losers]
          }
        end

        day = @ist_now.all_day
        exited = PositionTracker.live.where(status: :exited, exited_at: day).to_a
        realized = exited.sum { |t| t.last_pnl_rupees.to_f }
        unrealized = active.sum { |t| t.current_pnl_rupees.to_f }
        {
          realized_rupees: realized.round(2),
          unrealized_rupees: unrealized.round(2),
          total_rupees: (realized + unrealized).round(2),
          closed_trades: exited.size,
          winners: exited.count { |t| t.last_pnl_rupees.to_f.positive? },
          losers: exited.count { |t| t.last_pnl_rupees.to_f.negative? }
        }
      end

      # Realized global daily loss from Live::DailyLimits (Redis, shared with the
      # trading daemon). Unrealized loss is tracked in the daemon's in-process
      # ActiveCache and is not observable here, so utilization is realized-only.
      def daily_loss(capital)
        realized_loss = Live::DailyLimits.new.get_global_daily_loss.to_f
        cfg = AlgoConfig.fetch
        limit_pct = cfg.dig(:risk, :daily_limits, :global_limit_pct) ||
                    cfg.dig(:position_sizing, :daily_limits, :global_limit_pct)
        limit_rupees = limit_pct && capital.positive? ? capital * limit_pct.to_f : nil

        {
          realized_loss_rupees: realized_loss.round(2),
          global_limit_pct: limit_pct&.to_f,
          global_limit_rupees: limit_rupees&.round(2),
          utilization_pct: limit_rupees&.positive? ? (realized_loss / limit_rupees * 100).round(2) : nil,
          basis: 'realized_only'
        }
      end

      # ------------------------------------------------------------------
      # System health
      # ------------------------------------------------------------------

      def build_health(indices)
        status_cache = Live::SystemStatusCache.instance
        feed = status_cache.running?(:ws_market_feed)
        scheduler = status_cache.running?(:scheduler)
        order_updates = status_cache.running?(:ws_order_update)
        last_tick = Array(indices).filter_map { |i| parse_time(i.dig(:quote, :observed_at)) }.max
        reconciliation = latest_reconciliation

        components = {
          market_feed: heartbeat_component(feed, last_tick_at: last_tick&.iso8601, last_tick_age_seconds: age(last_tick)),
          signal_scheduler: heartbeat_component(scheduler),
          order_update_feed: heartbeat_component(order_updates, required: !paper?),
          trading_daemon: {
            status: feed || scheduler ? 'ok' : 'not_observed',
            evidence: 'derived from market_feed and signal_scheduler Redis heartbeats'
          },
          reconciliation: reconciliation[:component]
        }
        components.each { |name, c| @warnings << "#{name}_#{c[:status]}" unless HEALTHY_COMPONENT.include?(c[:status]) }

        { status: components.values.all? { |c| HEALTHY_COMPONENT.include?(c[:status]) } ? 'ok' : 'degraded',
          components: components }
      end

      def heartbeat_component(alive, required: true, **extra)
        status = if alive then 'ok'
                 elsif required then 'down'
                 else 'not_required'
                 end
        { status: status, evidence: "redis heartbeat (ttl #{Live::SystemStatusCache::HEARTBEAT_TTL.to_i}s)", **extra }
      end

      def latest_reconciliation
        @latest_reconciliation ||= begin
          run = ReconciliationRun.where(mode: mode.to_s).order(created_at: :desc).first
          unresolved = run ? ReconciliationDiscrepancy.where(reconciliation_run_id: run.id, resolution: nil).count : 0
          finished = run&.completed_at
          status = if run.nil? then 'unavailable'
                   elsif run.halted_trading then 'halted'
                   elsif %w[failed error].include?(run.status) then 'failed'
                   elsif finished.nil? || finished < @now - RECONCILIATION_MAX_AGE then 'stale'
                   elsif unresolved.positive? then 'discrepancies'
                   else 'ok'
                   end

          {
            component: {
              status: status,
              last_run_status: run&.status,
              completed_at: finished&.iso8601,
              age_seconds: age(finished),
              discrepancies_found: run&.discrepancies_found
            },
            discrepancies: { unresolved_count: unresolved, run_id: run&.id }
          }
        end
      end

      # ------------------------------------------------------------------
      # Overall freshness
      # ------------------------------------------------------------------

      def overall_freshness(snapshot)
        critical = Array(snapshot['indices']).flat_map do |idx|
          [idx.dig('quote', 'status'), idx.dig('regime', 'status'), idx.dig('smc', 'status')]
        end
        state = if critical.include?('error') || critical.empty? then 'degraded'
                elsif snapshot.dig('session', 'status') != 'open' then 'market_closed'
                elsif critical.all? { |s| LIVE_STATUSES.include?(s) } then 'live'
                else 'partial'
                end
        { 'state' => state, 'warning_count' => Array(snapshot['warnings']).size }
      end

      # ------------------------------------------------------------------
      # Helpers
      # ------------------------------------------------------------------

      def stringify(value)
        value.is_a?(Hash) ? value.deep_stringify_keys : nil
      end

      def numeric(value)
        Float(value).round(4)
      rescue ArgumentError, TypeError
        nil
      end

      def parse_time(value)
        return nil if value.blank?
        return Time.zone.at(value) if value.is_a?(Integer) # epoch seconds (e.g. VixGate ts)
        return value.in_time_zone if value.respond_to?(:in_time_zone) && !value.is_a?(String)

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def age(time)
        time ? (@now - time).round : nil
      end

      def smc_decision(value)
        SMC_DECISIONS[value.to_s.downcase]
      end

      def direction_label(value)
        case value.to_s.downcase
        when /bull/ then 'BULLISH'
        when /bear/ then 'BEARISH'
        when 'range', 'neutral', 'sideways' then 'NEUTRAL'
        else 'UNAVAILABLE'
        end
      end

      def zone_label(pd)
        return nil if pd.blank?
        return 'PREMIUM' if pd['premium'] == true
        return 'DISCOUNT' if pd['discount'] == true

        'EQUILIBRIUM'
      end

      def scalar_slice(value)
        hash = stringify(value)
        return nil unless hash

        hash.select { |_, v| v.is_a?(String) || v.is_a?(Numeric) || v.is_a?(Symbol) || v == true || v == false }
            .transform_values { |v| v.is_a?(Symbol) ? v.to_s : v }
            .first(6).to_h
      end

      def count_of(value)
        value.respond_to?(:size) ? value.size : nil
      end
    end
  end
end
