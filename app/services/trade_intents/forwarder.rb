# frozen_string_literal: true

module TradeIntents
  # With `execution.engine: agent`, Rails never places entries itself: an entry signal that passes the cheap
  # pre-checks becomes a trade-intent/1 row that options-trading-agent pulls. The agent picks strike, size, stop
  # and target and runs its own risk gate, so only checks that need no strike pick run here.
  class Forwarder
    DEFAULT_TTL_SECONDS = 20
    # Signal::Engine and the BOS engine carry no score; 0.5 marks "unscored". The agent does not gate on it.
    UNSCORED_CONFIDENCE = 0.5
    PRE_CHECKS = [
      Entries::Guards::CircuitBreakerGuard,
      Entries::Guards::EarliestEntryGuard,
      Entries::Guards::DailyLimitsGuard
    ].freeze
    # The agent refuses entries once its spot feed is older than its own FEED_STALE_MS (5 s by default).
    AGENT_FEED_STALE_MS = 10_000
    OPPOSITE_OPTION_TYPE = { 'BULLISH' => 'PE', 'BEARISH' => 'CE' }.freeze
    DIRECTIONS = { 'bullish' => 'BULLISH', 'long' => 'BULLISH', 'bearish' => 'BEARISH', 'short' => 'BEARISH' }.freeze

    Result = Data.define(:intent, :blocked_reason) do
      def forwarded? = !intent.nil?
    end

    class << self
      def agent_engine?
        AlgoConfig.fetch.dig(:execution, :engine).to_s == 'agent'
      end

      # `signal` keys: :strategy (required), :strategy_version, :signal_id, :confidence, :reasons.
      # @return [Result] the stored intent, or why the signal was not forwarded
      def forward(index_cfg:, direction:, signal:)
        intent_direction = DIRECTIONS[direction.to_s.downcase]
        return blocked("unknown_direction:#{direction}") unless intent_direction

        reason = pre_check_failure(index_cfg, intent_direction, signal[:strategy])
        return blocked(reason) if reason

        payload = build_payload(index_cfg, intent_direction, signal)
        Result.new(intent: persist(payload, signal[:signal_id]), blocked_reason: nil)
      end

      private

      def blocked(reason)
        Rails.logger.info("[TradeIntents::Forwarder] not forwarded: #{reason}")
        Result.new(intent: nil, blocked_reason: reason)
      end

      def pre_check_failure(index_cfg, intent_direction, strategy)
        return 'agent_intake_paper_only' unless mode == 'paper'
        return 'market_closed' if TradingSession::Service.market_closed?

        underlying = index_cfg[:key].to_s.upcase
        agent_refusal(underlying, intent_direction) || pending_conflict(underlying, intent_direction) ||
          guard_failure(index_cfg, strategy)
      end

      # Signals the agent would refuse anyway are not sent: it is offline, halted, without live ticks, outside its entry window, or
      # already holds the other side (two strategies disagreeing must not buy a CE and a PE on one index).
      def agent_refusal(underlying, intent_direction)
        snapshot = AgentSnapshot.read
        age_ms = snapshot && AgentSnapshot.age_ms(snapshot)
        return 'agent_offline' unless age_ms && age_ms < AgentSnapshot::STALE_AFTER_MS
        return "agent_kill_switch:#{snapshot.dig('kill_switch', 'reason')}" if snapshot.dig('kill_switch', 'engaged')
        return 'agent_feed_stale' unless snapshot['feed_age_ms'] && snapshot['feed_age_ms'] < AGENT_FEED_STALE_MS
        return 'outside_agent_entry_window' unless inside_entry_window?(snapshot['entry_window'])

        'agent_holds_opposite_side' if holds_side?(snapshot, underlying, OPPOSITE_OPTION_TYPE.fetch(intent_direction))
      end

      def inside_entry_window?(window)
        return true unless window

        now = Time.current.in_time_zone('Asia/Kolkata')
        minute = (now.hour * 60) + now.min
        minute >= window['start_minute'].to_i && minute < window['end_minute'].to_i
      end

      def holds_side?(snapshot, underlying, option_type)
        Array(snapshot['underlyings']).any? do |entry|
          entry['underlying'] == underlying && entry.dig('position', 'option_type') == option_type
        end
      end

      # ponytail: check-then-insert can race between runner threads; the agent's per-slot IDLE check drops the extra.
      def pending_conflict(underlying, intent_direction)
        pending = TradeIntent.pending.where(underlying: underlying).pick(:direction)
        return unless pending

        pending == intent_direction ? 'intent_already_pending' : 'opposite_intent_pending'
      end

      def guard_failure(index_cfg, strategy)
        context = { index_cfg: index_cfg, strategy_slug: strategy }
        PRE_CHECKS.each do |guard|
          verdict = guard.call(context)
          return verdict[:blocked] if verdict.is_a?(Hash) && verdict[:blocked]
        end
        nil
      end

      def build_payload(index_cfg, intent_direction, signal)
        now = Time.current
        source = { system: 'algo_scalper_api', strategy: signal[:strategy], strategy_version: signal[:strategy_version],
                   signal_id: signal[:signal_id] }
        {
          schema: 'trade-intent/1',
          intent_id: SecureRandom.uuid,
          issued_at: now.iso8601(3),
          expires_at: (now + ttl_seconds).iso8601(3),
          mode: mode,
          underlying: index_cfg[:key].to_s.upcase,
          direction: intent_direction,
          source: source.compact,
          confidence: (signal[:confidence] || UNSCORED_CONFIDENCE).to_f.clamp(0.0, 1.0),
          reasons: Array(signal[:reasons]).compact_blank.map(&:to_s),
          spot_hint: spot_for(index_cfg)
        }.compact
      end

      def persist(payload, signal_id)
        intent = TradeIntent.create!(
          intent_id: payload[:intent_id], mode: payload[:mode], underlying: payload[:underlying],
          direction: payload[:direction], source_strategy: payload.dig(:source, :strategy),
          confidence: payload[:confidence], payload: payload, expires_at: payload[:expires_at],
          strategy_signal_id: signal_id
        )
        Rails.logger.info("[TradeIntents::Forwarder] #{intent.underlying} #{intent.direction} → agent (#{intent.intent_id})")
        intent
      end

      def spot_for(index_cfg)
        Live::TickQuery.for_security(segment: index_cfg[:segment], security_id: index_cfg[:sid])&.ltp&.to_f
      rescue StandardError
        nil
      end

      def mode
        AlgoConfig.fetch.dig(:paper_trading, :enabled) == false ? 'live' : 'paper'
      end

      def ttl_seconds
        (AlgoConfig.fetch.dig(:execution, :intent_ttl_seconds) || DEFAULT_TTL_SECONDS).to_i
      end
    end
  end
end
