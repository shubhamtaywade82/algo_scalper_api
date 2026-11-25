# frozen_string_literal: true

module Api
  # Dashboard view of options-trading-agent: its heartbeat snapshot plus the latest intents and their outcomes.
  class AgentStatusesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    RECENT_INTENTS = 15

    def show
      snapshot = TradeIntents::AgentSnapshot.read
      age_ms = snapshot && TradeIntents::AgentSnapshot.age_ms(snapshot)

      render json: {
        engine: TradeIntents::Forwarder.agent_engine? ? 'agent' : 'rails',
        online: age_ms.present? && age_ms < TradeIntents::AgentSnapshot::STALE_AFTER_MS,
        age_ms: age_ms,
        snapshot: snapshot,
        recent_intents: TradeIntent.order(id: :desc).limit(RECENT_INTENTS).map { |intent| serialize(intent) }
      }
    end

    private

    def serialize(intent)
      {
        intent_id: intent.intent_id, underlying: intent.underlying, direction: intent.direction,
        strategy: intent.source_strategy, confidence: intent.confidence.to_f, issued_at: intent.created_at.iso8601,
        outcome: intent.display_outcome, code: intent.outcome_code, detail: intent.outcome_detail
      }
    end
  end
end
