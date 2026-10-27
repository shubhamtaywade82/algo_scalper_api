# frozen_string_literal: true

module Reports
  module MarketBrief
    # Deterministic "best qualified setup" for the brief.
    #
    # The report never qualifies trades itself. A candidate exists only when the
    # live strategy platform emitted a buy_call/buy_put signal today AND the entry
    # guard pipeline approved it (Strategies::Signal#outcome == 'executed').
    # Trade parameters come only from the PositionTracker linked to that signal.
    #
    # Ranking policy (v1): most recent approved signal wins; ties broken by id.
    #
    # Decisions:
    #   QUALIFIED — an approved candidate exists and no systemic blocker is active
    #   BLOCKED   — a systemic blocker (breaker, VIX gate, loss limit, feed, session) is active
    #   NO_TRADE  — nothing passed qualification today
    class SetupSelector
      DIRECTIONAL_ACTIONS = %w[buy_call buy_put].freeze
      OPTION_TYPE = { 'buy_call' => 'CE', 'buy_put' => 'PE' }.freeze
      NO_TRADE_MESSAGE = 'NO TRADE — No setup satisfies the current qualification and risk requirements.'

      def initialize(mode:, now:, index_keys:, session:, risk:, health:, market_context:, indices:)
        @mode = mode.to_s
        @now = now
        @index_keys = index_keys
        @session = session || {}
        @risk = risk || {}
        @health = health || {}
        @market_context = market_context || {}
        @indices = Array(indices)
      end

      def call
        signals = todays_signals
        approved = signals.where(outcome: 'executed').order(emitted_at: :desc, id: :desc)
        candidate = approved.first
        blockers = systemic_blockers

        decision = if blockers.any? then 'BLOCKED'
                   elsif candidate then 'QUALIFIED'
                   else 'NO_TRADE'
                   end

        {
          status: 'ok',
          decision: decision,
          message: decision == 'QUALIFIED' ? nil : NO_TRADE_MESSAGE,
          ranking_policy: 'latest_guard_approved_signal_today',
          approved_count: approved.count,
          evaluated_count: signals.count,
          candidate: candidate && candidate_payload(candidate),
          blockers: blockers,
          rejection_reasons: rejection_reasons(signals)
        }
      end

      private

      def todays_signals
        ist = @now.in_time_zone(TradingSession::Service::IST_TIMEZONE)
        ::Strategies::Signal.where(
          emitted_at: ist.beginning_of_day..@now,
          action: DIRECTIONAL_ACTIONS,
          instrument_key: @index_keys
        )
      end

      def candidate_payload(signal)
        tracker = signal.position_tracker
        {
          signal_id: signal.id,
          index_key: signal.instrument_key,
          option_type: OPTION_TYPE[signal.action],
          strategy: signal.strategy_record&.slug,
          strategy_reason: signal.reason.to_s.truncate(240),
          emitted_at: signal.emitted_at&.iso8601,
          age_seconds: signal.emitted_at ? (@now - signal.emitted_at).round : nil,
          trade: tracker ? trade_payload(tracker) : nil,
          trade_link_status: tracker ? 'linked' : 'not_linked'
        }
      end

      # Validated levels as recorded/derived by the existing position services.
      def trade_payload(tracker)
        entry = tracker.entry_price.to_f
        quantity = tracker.quantity.to_i
        active = tracker.status.to_s == 'active'
        levels = if active
                   Positions::Serializer.open(tracker).slice(:sl_price, :tp_price)
                 else
                   { sl_price: Positions::Serializer.sl_price(tracker, entry),
                     tp_price: Positions::Serializer.tp_price(tracker, entry) }
                 end
        sl = levels[:sl_price]&.to_f
        tp = levels[:tp_price]&.to_f
        risk_per_unit = sl && entry.positive? ? entry - sl : nil
        reward_per_unit = tp && entry.positive? ? tp - entry : nil

        {
          position_tracker_id: tracker.id,
          symbol: tracker.symbol,
          strike: tracker.atm_strike&.to_f,
          expiry: tracker.expiry_date&.iso8601,
          entry_price: entry.positive? ? entry.round(2) : nil,
          stop_loss: sl&.round(2),
          target: tp&.round(2),
          reward_to_risk: risk_per_unit&.positive? && reward_per_unit ? (reward_per_unit / risk_per_unit).round(2) : nil,
          quantity: quantity.positive? ? quantity : nil,
          capital_required: entry.positive? && quantity.positive? ? (entry * quantity).round(2) : nil,
          spread_guard_pct: tracker.spread_guard_pct&.to_f,
          position_status: tracker.status.to_s,
          exit_reason: tracker.exit_reason
        }
      end

      def rejection_reasons(signals)
        signals.where(outcome: 'blocked_by_guard')
               .group(Arel.sql("COALESCE(metadata->>'entry_result_reason', 'unspecified')"))
               .count
               .sort_by { |reason, count| [-count, reason.to_s] }
               .first(SnapshotBuilder::REJECTION_REASON_LIMIT)
               .map { |reason, count| { reason: reason.to_s.truncate(120), count: count } }
      end

      def systemic_blockers
        blockers = []
        blockers << 'circuit_breaker_tripped' if @risk.dig(:circuit_breaker, :tripped)
        blockers << 'vix_gate_blocks_entries' if @market_context.dig(:vix, :entry_allowed) == false
        blockers << 'vix_force_exit_active' if @market_context.dig(:vix, :force_exit_active)
        utilization = @risk.dig(:daily_loss, :utilization_pct)
        blockers << 'daily_loss_limit_reached' if utilization && utilization >= 100
        blockers << "session_#{@session[:status]}" if @session[:status].present? && @session[:status] != 'open'
        blockers << 'outside_entry_window' if @session[:status] == 'open' && @session[:entry_window_open] == false
        blockers << 'market_feed_down' if @health.dig(:components, :market_feed, :status) == 'down'
        blockers << 'reconciliation_halted' if @health.dig(:components, :reconciliation, :status) == 'halted'
        blockers << 'risk_state_unavailable' if @risk[:status] == 'error'
        if @session[:status] == 'open' && @indices.any? && @indices.none? { |i| i.dig(:quote, :status) == 'live' }
          blockers << 'no_live_index_quotes'
        end
        blockers
      end
    end
  end
end
