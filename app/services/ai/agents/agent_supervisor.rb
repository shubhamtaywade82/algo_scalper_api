# frozen_string_literal: true

require 'singleton'

module Ai
  module Agents
    # Safety-architecture layer 2 from the review blueprint (§8.10): a
    # capability-based access control point every agent's authority is
    # checked against, plus a status view (would back a future dashboard,
    # per the report's "AgentSupervisor" recommendation).
    #
    # Every agent is :advisor with a fixed, read-only capability set, EXCEPT
    # DynamicConfigAgent, deliberately promoted to :level_2 with the single
    # extra capability `apply_config` (see DynamicConfigAgent — it is the
    # only class in the codebase that calls AlgoConfig::DocumentStore).
    # There is still no generic setter to promote an agent's level; a second
    # Level 2 agent means editing LEVEL_2_AGENT_NAMES here, not a runtime call.
    class AgentSupervisor
      include Singleton

      ADVISOR_CAPABILITIES = %i[
        read_market read_positions read_config
        suggest_strategy suggest_calibration
        log_decision publish_event
      ].freeze

      LEVEL_2_CAPABILITIES = %i[apply_config].freeze
      LEVEL_2_AGENT_NAMES = %w[dynamic_config_agent].freeze

      # Never grantable to any agent, regardless of level — see class doc.
      FORBIDDEN_CAPABILITIES = %i[
        place_order cancel_order modify_order
        modify_risk_limit trip_circuit_breaker
      ].freeze

      AGENT_NAMES = %w[
        market_analysis_agent
        strategy_selection_agent
        risk_management_agent
        execution_agent
        post_trade_analysis_agent
        calibration_agent
        dynamic_config_agent
      ].freeze

      def authority_level(agent_name)
        LEVEL_2_AGENT_NAMES.include?(agent_name.to_s) ? :level_2 : :advisor
      end

      def capability_granted?(agent_name, capability)
        cap = capability.to_sym
        return true if LEVEL_2_AGENT_NAMES.include?(agent_name.to_s) && LEVEL_2_CAPABILITIES.include?(cap)

        ADVISOR_CAPABILITIES.include?(cap)
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
