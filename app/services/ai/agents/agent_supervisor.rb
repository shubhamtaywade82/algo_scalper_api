# frozen_string_literal: true

require 'singleton'

module Ai
  module Agents
    # Safety-architecture layer 2 from the review blueprint (§8.10): a
    # capability-based access control point every agent's authority is
    # checked against, plus a status view (would back a future dashboard,
    # per the report's "AgentSupervisor" recommendation).
    #
    # This phase hardcodes every agent to :advisor with a fixed, read-only
    # capability set — there is deliberately no setter to promote an agent's
    # authority level here. Wiring real promotion (Level 2+, an autonomy
    # budget, a circuit-breaker cascade) is future work the report scopes at
    # Phase 3+; this class exists now so that boundary has one owner instead
    # of being reimplemented ad hoc per agent.
    class AgentSupervisor
      include Singleton

      ADVISOR_CAPABILITIES = %i[
        read_market read_positions read_config
        suggest_strategy suggest_calibration
        log_decision publish_event
      ].freeze

      # Never grantable in this phase, regardless of caller — see class doc.
      FORBIDDEN_CAPABILITIES = %i[
        place_order cancel_order modify_order
        modify_risk_limit trip_circuit_breaker apply_config
      ].freeze

      AGENT_NAMES = %w[
        market_analysis_agent
        strategy_selection_agent
        risk_management_agent
        execution_agent
        post_trade_analysis_agent
        calibration_agent
      ].freeze

      def authority_level(_agent_name)
        :advisor
      end

      def capability_granted?(_agent_name, capability)
        ADVISOR_CAPABILITIES.include?(capability.to_sym)
      end

      def capability_forbidden?(capability)
        FORBIDDEN_CAPABILITIES.include?(capability.to_sym)
      end

      # @return [Hash] agent_name => { authority_level:, decisions_today:, last_decision_at:, last_error_at: }
      def status
        AGENT_NAMES.index_with { |name| agent_status(name) }
      end

      private

      def agent_status(name)
        scope = AgentDecisionLog.for_agent(name)
        last = scope.recent.first
        {
          authority_level: authority_level(name).to_s,
          decisions_today: scope.where(created_at: Time.current.beginning_of_day..).count,
          last_decision_at: last&.created_at,
          last_decision_type: last&.decision_type,
          last_error_at: scope.failed.recent.first&.created_at
        }
      rescue StandardError => e
        { authority_level: 'advisor', error: e.message }
      end
    end
  end
end
