# frozen_string_literal: true

module Ai
  module Agents
    # Shared scaffolding for the advisor-level agentic AI layer proposed in
    # the architecture review ("Agentic AI Integration Blueprint" §8).
    #
    # Every agent under Ai::Agents::* is Level 1 (Advisor) only in this phase:
    # it reads existing services/models, produces a recommendation, and logs
    # it to AgentDecisionLog. None of them place, modify, or cancel orders,
    # mutate AlgoConfig, or override any guard/exit rule — see AgentSupervisor
    # for the capability boundary this is built against. Promoting an agent
    # to Level 2 (bounded autonomous execution) is a deliberate future change,
    # not something #run can be talked into by a caller.
    class BaseAgent
      AUTHORITY_LEVEL = :advisor

      class << self
        def agent_name
          name.demodulize.underscore
        end
      end

      # Runs the agent, logging exactly one AgentDecisionLog row (success or
      # failure) per call so AgentSupervisor#status has a complete trail.
      # @return [Hash] result hash from #perform, or {ok: false, error:} on failure
      def run(**context)
        result = perform(**context)
        log_decision(
          context: context,
          output: result[:output] || {},
          decision_type: result.fetch(:decision_type, 'decision'),
          confidence: result[:confidence],
          published_event: result[:published_event]
        )
        result
      rescue StandardError => e
        Rails.logger.error("[Ai::Agents::#{self.class.agent_name}] #{e.class} - #{e.message}")
        log_decision(context: context, output: {}, decision_type: 'error', error: "#{e.class}: #{e.message}")
        { ok: false, error: e.message }
      end

      private

      # @return [Hash] :decision_type, :output, optional :confidence, :published_event
      def perform(**_context)
        raise NotImplementedError, "#{self.class} must implement #perform"
      end

      def log_decision(context:, output:, decision_type:, confidence: nil, published_event: nil, error: nil)
        AgentDecisionLog.create!(
          agent_name: self.class.agent_name,
          authority_level: AUTHORITY_LEVEL.to_s,
          decision_type: decision_type.to_s,
          input_context: sanitize(context),
          output: sanitize(output),
          confidence: confidence,
          published_event: published_event&.to_s,
          error: error
        )
      rescue StandardError => e
        Rails.logger.error("[Ai::Agents::#{self.class.agent_name}] failed to persist decision log: #{e.message}")
      end

      # Observational only — see Core::EventBus and CLAUDE.md: direct method
      # calls are the live trading system's real communication layer, this
      # is for downstream visibility/logging, not control flow.
      def publish(event_type, payload)
        Core::EventBus.instance.publish(event_type, payload)
      rescue StandardError => e
        Rails.logger.warn("[Ai::Agents::#{self.class.agent_name}] publish(#{event_type}) failed: #{e.message}")
      end

      def sanitize(hash)
        return {} unless hash.is_a?(Hash)

        JSON.parse(hash.to_json)
      rescue StandardError
        {}
      end
    end
  end
end
